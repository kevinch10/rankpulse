import Foundation
import Observation
import UserNotifications
import WidgetKit

/// Which notifications the user wants (all on by default).
enum NotificationKind: String, CaseIterable, Identifiable {
    case pointsAndPlaces, rivalWatch, matchReminders, milestones, weeklyDigest, officialRelease
    var id: String { rawValue }

    var title: String {
        switch self {
        case .pointsAndPlaces: "Points & places"
        case .rivalWatch: "Rival watch"
        case .matchReminders: "Match reminders"
        case .milestones: "Milestones"
        case .weeklyDigest: "Weekly digest"
        case .officialRelease: "Official ranking released"
        }
    }

    var detail: String {
        switch self {
        case .pointsAndPlaces: "When a favourite gains or loses points or places after a result."
        case .rivalWatch: "When a favourite overtakes another team, or another team overtakes it."
        case .matchReminders: "An hour before a favourite kicks off, with the points at stake."
        case .milestones: "Reaching #1, or entering or leaving the top 10, 20, 50 or 100."
        case .weeklyDigest: "Every Monday at 9:00 — each favourite's week: places, points, results and next match."
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
        if kind == .weeklyDigest && !on {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.digestID])
        }
        if kind == .weeklyDigest && on { onChange?() }
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
            defaults.set(Self.rankMap(data), forKey: "lastLiveRanks")
            save()
            return
        }

        // The whole live table as of the last check, to spot overtakes.
        let previousTable = defaults.dictionary(forKey: "lastLiveRanks") as? [String: Int]
        let table = Self.rankMap(data)
        defaults.set(table, forKey: "lastLiveRanks")
        let names = Dictionary(uniqueKeysWithValues: data.teams.map { ($0.code, $0.name) })

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
            let rivals = isEnabled(.rivalWatch) && places != 0 && previousTable != nil
                ? Self.overtakes(of: code, before: previousTable ?? [:], now: table).map { (passed: $0.passed.compactMap { names[$0] }, passedBy: $0.passedBy.compactMap { names[$0] }) }
                : nil
            let match = pointsMoved ? data.results.first { $0.isCounted && $0.involves(code) } : nil
            if isEnabled(.pointsAndPlaces) || milestone != nil {
                await post(team: team, delta: pointsMoved ? delta : nil, places: places, match: match,
                           milestone: milestone, rivals: rivals)
            } else if let rivals, !(rivals.passed.isEmpty && rivals.passedBy.isEmpty) {
                await postRivals(team: team, passed: rivals.passed, passedBy: rivals.passedBy, match: match)
            }
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

    static func rankMap(_ data: RankingData) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: data.teams.map { ($0.code, $0.liveRank) })
    }

    /// Teams a favourite passed, and teams that passed it, between two tables.
    static func overtakes(of code: String, before: [String: Int], now: [String: Int]) -> (passed: [String], passedBy: [String])? {
        guard let was = before[code], let isNow = now[code] else { return nil }
        var passed: [(String, Int)] = [], passedBy: [(String, Int)] = []
        for (other, otherNow) in now where other != code {
            guard let otherWas = before[other] else { continue }
            if otherWas < was && otherNow > isNow { passed.append((other, otherNow)) }
            if otherWas > was && otherNow < isNow { passedBy.append((other, otherNow)) }
        }
        // nearest rivals first
        return (passed.sorted { $0.1 < $1.1 }.map(\.0), passedBy.sorted { $0.1 > $1.1 }.map(\.0))
    }

    /// "Argentina", "Argentina and France", "Argentina, France and 2 others".
    static func nameList(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            let rest = names.count - 2
            return "\(names[0]), \(names[1]) and \(rest) other\(rest == 1 ? "" : "s")"
        }
    }

    /// "Spain overtook Argentina", "Morocco overtook Spain".
    static func rivalTitle(team: String, passed: [String], passedBy: [String]) -> String {
        switch (passed.isEmpty, passedBy.isEmpty) {
        case (false, true): return "\(team) overtook \(nameList(passed))"
        case (true, false): return "\(nameList(passedBy)) overtook \(team)"
        case (false, false): return "\(team) overtook \(nameList(passed)); \(nameList(passedBy)) overtook \(team)"
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

    private func post(team: Team, delta: Double?, places: Int, match: Match?, milestone: String? = nil,
                      rivals: (passed: [String], passedBy: [String])? = nil) async {
        let content = UNMutableNotificationContent()
        let summary = Self.title(team: team.name, delta: delta, places: places)
        content.title = milestone ?? summary
        var lines: [String] = milestone == nil ? [] : [summary]
        if let match {
            lines.append("\(match.homeName) \(match.scoreText) \(match.awayName) · \(match.competition)")
        }
        if let rivals, !rivals.passed.isEmpty {
            lines.append("Overtook \(Self.nameList(rivals.passed))")
        }
        if let rivals, !rivals.passedBy.isEmpty {
            lines.append("Overtaken by \(Self.nameList(rivals.passedBy))")
        }
        if match == nil && places != 0 && (rivals.map { $0.passed.isEmpty && $0.passedBy.isEmpty } ?? true) {
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

    private func postRivals(team: Team, passed: [String], passedBy: [String], match: Match?) async {
        let content = UNMutableNotificationContent()
        content.title = Self.rivalTitle(team: team.name, passed: passed, passedBy: passedBy)
        var lines: [String] = []
        if let match { lines.append("\(match.homeName) \(match.scoreText) \(match.awayName) · \(match.competition)") }
        lines.append("\(team.name) is now #\(team.liveRank) live")
        content.body = lines.joined(separator: "\n")
        content.sound = .default
        content.threadIdentifier = team.code
        let request = UNNotificationRequest(identifier: "rival-\(team.code)-\(team.liveRank)-\(team.livePoints)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: Weekly digest

    static let digestID = "weekly-digest"

    /// Most recent Monday 09:00 at or before `date`.
    static func weekStart(for date: Date = .now) -> Date {
        let cal = Calendar.current
        var comps = DateComponents(hour: 9, minute: 0, weekday: 2)
        comps.calendar = cal
        return cal.nextDate(after: date, matching: comps, matchingPolicy: .nextTime, direction: .backward) ?? date
    }

    /// (Re)schedules next Monday's digest from the latest data. Places are
    /// measured from each favourite's rank at the start of the week; points
    /// and results come from this week's counted matches.
    func scheduleWeeklyDigest(_ data: RankingData) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.digestID])

        // Start a new weekly baseline once a week begins.
        let start = Self.weekStart()
        let startKey = ISO8601DateFormatter().string(from: start)
        var weekRanks = defaults.dictionary(forKey: "weekStartRanks") as? [String: Int] ?? [:]
        if defaults.string(forKey: "weekStartDate") != startKey {
            weekRanks = Self.rankMap(data)
            defaults.set(weekRanks, forKey: "weekStartRanks")
            defaults.set(startKey, forKey: "weekStartDate")
        }

        guard isEnabled(.weeklyDigest), notificationsAllowed != false,
              let content = digestContent(data, since: start, weekRanks: weekRanks) else { return }
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 9, minute: 0, weekday: 2), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: Self.digestID, content: content, trigger: trigger))
    }

    /// Shows this week's digest right away (from the settings screen).
    func sendDigestPreview(_ data: RankingData) async {
        if notificationsAllowed == nil { await requestPermission() }
        let weekRanks = defaults.dictionary(forKey: "weekStartRanks") as? [String: Int] ?? [:]
        guard let content = digestContent(data, since: Self.weekStart(), weekRanks: weekRanks) else { return }
        content.title += " (preview)"
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "digest-preview-\(Date.now.timeIntervalSince1970)", content: content, trigger: nil))
    }

    private func digestContent(_ data: RankingData, since start: Date, weekRanks: [String: Int]) -> UNMutableNotificationContent? {
        let mine = data.teams.filter { codes.contains($0.code) }.sorted { $0.liveRank < $1.liveRank }
        guard !mine.isEmpty else { return nil }

        let lines = mine.prefix(4).map { t -> String in
            var parts = ["\(t.name) #\(t.liveRank)"]
            if let was = weekRanks[t.code], was != t.liveRank {
                parts[0] += was > t.liveRank ? " ▲\(was - t.liveRank)" : " ▼\(t.liveRank - was)"
            }
            let played = data.results.filter { m in
                m.status == 0 && m.involves(t.code) && (m.kickoffDate.map { $0 >= start } ?? false)
            }
            if played.isEmpty {
                parts.append("no matches")
            } else {
                let pts = played.compactMap { $0.delta(for: t.code) }.reduce(0, +)
                parts.append("\(pts.signedShort) pts")
                parts.append("\(played.count) result\(played.count == 1 ? "" : "s")")
            }
            if let next = data.fixtures.first(where: { $0.involves(t.code) }) {
                let opponent = next.home == t.code ? next.away : next.home
                let day = next.kickoffDate?.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) ?? next.date
                parts.append("next v \(opponent) \(day)")
            }
            return parts.joined(separator: " · ")
        }

        let content = UNMutableNotificationContent()
        content.title = "Your week in the rankings"
        content.body = lines.joined(separator: "\n")
        content.sound = .default
        return content
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
