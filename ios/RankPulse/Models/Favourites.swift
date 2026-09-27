import Foundation
import Observation
import UserNotifications

/// Favourite teams, plus the points each one had when we last told the user
/// about it, so a refresh can notify only about changes since then.
@MainActor
@Observable
final class Favourites {
    private(set) var codes: Set<String>
    private(set) var notificationsAllowed: Bool?

    private let defaults = UserDefaults.standard
    private var baselines: [String: Double]

    init() {
        codes = Set(defaults.stringArray(forKey: "favourites") ?? [])
        baselines = defaults.dictionary(forKey: "favouriteBaselines") as? [String: Double] ?? [:]
    }

    func contains(_ code: String) -> Bool { codes.contains(code) }

    func toggle(_ team: Team) {
        if codes.remove(team.code) == nil {
            codes.insert(team.code)
            baselines[team.code] = team.livePoints
            Task { await requestPermission() }
        } else {
            baselines[team.code] = nil
        }
        save()
    }

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        notificationsAllowed = granted
    }

    func refreshPermissionStatus() async {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: notificationsAllowed = true
        case .denied: notificationsAllowed = false
        default: notificationsAllowed = nil  // not asked yet
        }
    }

    /// Posts a notification for every favourite whose live points moved since
    /// the last check, then moves the baseline forward.
    func notifyChanges(in data: RankingData) async {
        var changed = false
        for code in codes {
            guard let team = data.teams.first(where: { $0.code == code }) else { continue }
            guard let before = baselines[code] else {
                baselines[code] = team.livePoints; changed = true; continue
            }
            let delta = team.livePoints - before
            guard abs(delta) >= 0.01 else { continue }
            baselines[code] = team.livePoints
            changed = true
            await post(team: team, delta: delta, match: data.results.first { $0.isCounted && $0.involves(code) })
        }
        if changed { save() }
    }

    private func post(team: Team, delta: Double, match: Match?) async {
        let content = UNMutableNotificationContent()
        content.title = "\(team.name) \(delta > 0 ? "gained" : "lost") \(abs(delta).formatted(.number.precision(.fractionLength(2)))) pts"
        var lines: [String] = []
        if let match {
            lines.append("\(match.homeName) \(match.scoreText) \(match.awayName) · \(match.competition)")
        }
        lines.append("Now #\(team.liveRank) live with \(team.livePoints.formatted(.number.precision(.fractionLength(2)))) pts")
        content.body = lines.joined(separator: "\n")
        content.sound = .default
        content.threadIdentifier = team.code
        content.userInfo = ["team": team.code]
        let request = UNNotificationRequest(identifier: "points-\(team.code)-\(team.livePoints)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func save() {
        defaults.set(Array(codes), forKey: "favourites")
        defaults.set(baselines, forKey: "favouriteBaselines")
    }
}
