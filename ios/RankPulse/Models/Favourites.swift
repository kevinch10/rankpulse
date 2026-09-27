import Foundation
import Observation
import UserNotifications
import WidgetKit

/// Which notifications the user wants (all on by default).
enum NotificationKind: String, CaseIterable, Identifiable {
    case pointsAndPlaces, matchReminders, milestones, officialRelease
    var id: String { rawValue }

    var title: String {
        switch self {
        case .pointsAndPlaces: "Points & places"
        case .matchReminders: "Match reminders"
        case .milestones: "Milestones"
        case .officialRelease: "Official ranking released"
        }
    }

    var detail: String {
        switch self {
        case .pointsAndPlaces: "When a favourite gains or loses points or places after a result."
        case .matchReminders: "An hour before a favourite kicks off, with the points at stake."
        case .milestones: "Reaching #1, or entering or leaving the top 10, 20, 50 or 100."
        case .officialRelease: "When FIFA publishes a new official ranking, with where your teams stand."
        }
    }

    var isOn: Bool {
        UserDefaults.standard.object(forKey: "notify.\(rawValue)") as? Bool ?? true
    }
}

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

    private(set) var enabled: [NotificationKind: Bool] = [:]
    /// Called when favourites change (the store re-plans match reminders).
    var onChange: (() -> Void)?

    func isEnabled(_ kind: NotificationKind) -> Bool { enabled[kind] ?? kind.isOn }

    func setEnabled(_ kind: NotificationKind, _ on: Bool) {
        enabled[kind] = on
        defaults.set(on, forKey: "notify.\(kind.rawValue)")
        if kind == .matchReminders && !on {
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                let ids = requests.map(\.identifier).filter { $0.hasPrefix("reminder-") }
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    init() {
        let saved = defaults.stringArray(forKey: "favourites") ?? []
        codes = Set(saved)
        SharedStore.favourites = saved  // keep the widget in sync for existing users
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
            onChange?()
        } else {
            baselines[team.code] = nil
            rankBaselines[team.code] = nil
            onChange?()
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
        // A new official release resets the live table; announce it once and
        // move every baseline silently instead of sending per-team alerts.
        let release = data.official.pubDate
        let lastRelease = defaults.string(forKey: "lastOfficialRelease")
        defaults.set(release, forKey: "lastOfficialRelease")
        if let lastRelease, lastRelease != release {
            if isEnabled(.officialRelease) { await postOfficialRelease(data) }
            for code in codes {
                guard let t = data.teams.first(where: { $0.code == code }) else { continue }
                baselines[code] = t.livePoints
                rankBaselines[code] = t.liveRank
            }
            save()
            return
        }

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
            let milestone = isEnabled(.milestones) ? Self.milestone(from: rankBefore, to: team.liveRank, team: team.name) : nil
            guard isEnabled(.pointsAndPlaces) || milestone != nil else { continue }
            let match = pointsMoved ? data.results.first { $0.isCounted && $0.involves(code) } : nil
            await post(team: team, delta: pointsMoved ? delta : nil, places: places, match: match, milestone: milestone)
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

    /// "Spain is now #1", "Japan entered the top 10", "Mexico dropped out of the top 20".
    static func milestone(from before: Int, to now: Int, team: String) -> String? {
        if now == 1 && before != 1 { return "🏆 \(team) is now #1 in the world" }
        if before == 1 && now != 1 { return "\(team) lost the #1 spot" }
        for tier in [10, 20, 50, 100] {
            if before > tier && now <= tier { return "⭐️ \(team) entered the top \(tier)" }
            if before <= tier && now > tier { return "\(team) dropped out of the top \(tier)" }
        }
        return nil
    }

    private func post(team: Team, delta: Double?, places: Int, match: Match?, milestone: String? = nil) async {
        let content = UNMutableNotificationContent()
        let summary = Self.title(team: team.name, delta: delta, places: places)
        content.title = milestone ?? summary
        var lines: [String] = milestone == nil ? [] : [summary]
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

    private func postOfficialRelease(_ data: RankingData) async {
        let mine = data.teams.filter { codes.contains($0.code) }.sorted { $0.officialRank < $1.officialRank }
        let shown = mine.isEmpty ? Array(data.teams.prefix(3)) : Array(mine.prefix(4))
        let content = UNMutableNotificationContent()
        content.title = "New official FIFA ranking published"
        content.body = shown.map { t in
            let move = t.previousRank - t.officialRank
            let arrow = move > 0 ? " ▲\(move)" : move < 0 ? " ▼\(-move)" : ""
            return "\(t.name) #\(t.officialRank)\(arrow)"
        }.joined(separator: " · ")
        content.sound = .default
        let request = UNNotificationRequest(identifier: "release-\(data.official.pubDate)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Schedules a reminder an hour before each favourite's upcoming matches
    /// (next two weeks; iOS allows 64 pending notifications per app).
    func scheduleMatchReminders(_ data: RankingData) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("reminder-") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard isEnabled(.matchReminders), notificationsAllowed != false else { return }

        let horizon = Date().addingTimeInterval(14 * 24 * 3600)
        let upcoming = data.fixtures.filter { m in
            (codes.contains(m.home) || codes.contains(m.away)) && (m.kickoffDate.map { $0 > .now && $0 < horizon } ?? false)
        }
        for m in upcoming.prefix(40) {
            guard let kickoff = m.kickoffDate else { continue }
            let fire = kickoff.addingTimeInterval(-3600)
            guard fire > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(m.homeName) v \(m.awayName) in 1 hour"
            var body = m.competition
            let fav = codes.contains(m.home) ? m.home : m.away
            let name = fav == m.home ? m.homeName : m.awayName
            if let p = m.prediction {
                let side = fav == m.home ? p.home : p.away
                let parts = [("win", side["win"]), ("draw", side["draw"]), ("loss", side["loss"])]
                    .compactMap { label, v in v.map { "\(label) \($0.signedShort)" } }
                body += "\n\(name) points at stake: " + parts.joined(separator: " · ")
            }
            content.body = body
            content.sound = .default
            content.threadIdentifier = fav
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let request = UNNotificationRequest(identifier: "reminder-\(m.id)", content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(request)
        }
    }

    private func save() {
        defaults.set(Array(codes), forKey: "favourites")
        SharedStore.favourites = Array(codes)
        WidgetCenter.shared.reloadAllTimelines()
        defaults.set(baselines, forKey: "favouriteBaselines")
        defaults.set(rankBaselines, forKey: "favouriteRankBaselines")
    }
}
