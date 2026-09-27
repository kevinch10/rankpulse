import Foundation
import Observation
import UserNotifications

/// Favourite teams, plus the points and live rank each one had when we last
/// told the user about it, so a refresh notifies only about changes since.
@MainActor
@Observable
final class Favourites {
    private(set) var codes: Set<String>
    private(set) var notificationsAllowed: Bool?

    private let defaults = UserDefaults.standard
    private var baselines: [String: Double]
    private var rankBaselines: [String: Int]

    init() {
        codes = Set(defaults.stringArray(forKey: "favourites") ?? [])
        baselines = defaults.dictionary(forKey: "favouriteBaselines") as? [String: Double] ?? [:]
        rankBaselines = defaults.dictionary(forKey: "favouriteRankBaselines") as? [String: Int] ?? [:]
    }

    func contains(_ code: String) -> Bool { codes.contains(code) }

    func toggle(_ team: Team) {
        if codes.remove(team.code) == nil {
            codes.insert(team.code)
            baselines[team.code] = team.livePoints
            rankBaselines[team.code] = team.liveRank
            Task { await requestPermission() }
        } else {
            baselines[team.code] = nil
            rankBaselines[team.code] = nil
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

    /// Posts a notification for every favourite whose live points or live
    /// rank moved since the last check, then moves the baselines forward.
    func notifyChanges(in data: RankingData) async {
        var changed = false
        for code in codes {
            guard let team = data.teams.first(where: { $0.code == code }) else { continue }
            guard let before = baselines[code], let rankBefore = rankBaselines[code] else {
                baselines[code] = team.livePoints
                rankBaselines[code] = team.liveRank
                changed = true
                continue
            }
            let delta = team.livePoints - before
            let places = rankBefore - team.liveRank  // positive = moved up
            let pointsMoved = abs(delta) >= 0.01
            guard pointsMoved || places != 0 else { continue }
            baselines[code] = team.livePoints
            rankBaselines[code] = team.liveRank
            changed = true
            let match = pointsMoved ? data.results.first { $0.isCounted && $0.involves(code) } : nil
            await post(team: team, delta: pointsMoved ? delta : nil, places: places, match: match)
        }
        if changed { save() }
    }

    static func title(team: String, delta: Double?, places: Int) -> String {
        let pts = delta.map { "\($0 > 0 ? "gained" : "lost") \(abs($0).formatted(.number.precision(.fractionLength(2)))) pts" }
        let move = places == 0 ? nil
            : "\(places > 0 ? "moved up" : "dropped") \(abs(places)) place\(abs(places) == 1 ? "" : "s")"
        switch (pts, move) {
        case let (p?, m?): return "\(team) \(p) and \(m)"
        case let (p?, nil): return "\(team) \(p)"
        case let (nil, m?): return "\(team) \(m)"
        default: return team
        }
    }

    private func post(team: Team, delta: Double?, places: Int, match: Match?) async {
        let content = UNMutableNotificationContent()
        content.title = Self.title(team: team.name, delta: delta, places: places)
        var lines: [String] = []
        if let match {
            lines.append("\(match.homeName) \(match.scoreText) \(match.awayName) · \(match.competition)")
        } else if places != 0 {
            lines.append("Other results moved the table.")
        }
        let rankLine = places == 0 ? "Still #\(team.liveRank)" : "Now #\(team.liveRank)"
        lines.append("\(rankLine) live with \(team.livePoints.formatted(.number.precision(.fractionLength(2)))) pts")
        content.body = lines.joined(separator: "\n")
        content.sound = .default
        content.threadIdentifier = team.code
        content.userInfo = ["team": team.code]
        let request = UNNotificationRequest(identifier: "change-\(team.code)-\(team.livePoints)-\(team.liveRank)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func save() {
        defaults.set(Array(codes), forKey: "favourites")
        defaults.set(baselines, forKey: "favouriteBaselines")
        defaults.set(rankBaselines, forKey: "favouriteRankBaselines")
    }
}
