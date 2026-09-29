import Foundation
import Observation

@MainActor
@Observable
final class RankingStore {
    private(set) var data: RankingData?
    /// The last server data, before live scores are layered on.
    private var base: RankingData?
    private var live: [String: LiveScore] = [:]
    private(set) var liveCheckedAt: Date?
    private var serverFetchedAt: Date?
    private(set) var error: String?
    private(set) var isLoading = false
    private(set) var isSnapshot = false
    private(set) var historyFailed = false
    /// Set by a widget tap: the Rankings tab opens this team.
    var openTeamCode: String?
    /// Results from the year before the latest official ranking.
    private(set) var history: [Match] = []
    private(set) var historyFrom: String?
    private var historyLoadedAt: Date?

    private var confedByCode: [String: String] = [:]
    let favourites = Favourites()

    init() {
        favourites.onChange = { [weak self] in
            Task { @MainActor in
                guard let self, let data = self.data else { return }
                await self.favourites.scheduleMatchReminders(data)
                await self.favourites.scheduleWeeklyDigest(data)
            }
        }
    }
    private static let cacheURL = URL.cachesDirectory.appending(path: "rankings.json")

    /// Shows cached or bundled data immediately, then fetches the latest.
    func load() async {
        if data == nil, let local = Self.readLocal() {
            apply(local.data, snapshot: local.bundled)
        }
        await favourites.refreshPermissionStatus()
        await refresh()
    }

    func refresh() async {
        guard let url = Config.dataURL else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (bytes, _) = try await URLSession.shared.data(for: request)
            let fresh = try JSONDecoder().decode(RankingData.self, from: bytes)
            try? bytes.write(to: Self.cacheURL)
            apply(fresh, snapshot: false)
            serverFetchedAt = Date()
            error = nil
            await pollLive(notify: false)
            if let data {
                await favourites.notifyChanges(in: data)
                await favourites.scheduleMatchReminders(data)
                await favourites.scheduleWeeklyDigest(data)
            }
        } catch {
            self.error = Self.explain(error, haveData: data != nil)
        }
    }

    /// Live scores from FIFA for matches on now; favourites get alerts at full time.
    func pollLive(notify: Bool = true) async {
        guard let base else { return }
        let wanted = LiveScores.candidates(base)
        guard !wanted.isEmpty else { liveCheckedAt = nil; return }
        do {
            let fresh = try await LiveScores.fetch(wanted)
            live.merge(fresh) { _, new in new }
            liveCheckedAt = Date()
            data = LiveScores.apply(live, to: base)
            if notify, let data { await favourites.notifyChanges(in: data) }
        } catch {
            // keep the last scores; try again next minute
        }
    }

    /// Runs while the app is open: live scores every minute, server data every 10.
    func liveLoop() async {
        while !Task.isCancelled {
            if serverFetchedAt.map({ Date().timeIntervalSince($0) > 600 }) ?? false {
                await refresh()
            } else {
                await pollLive()
            }
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// When the data was last rebuilt on the server.
    var updatedAt: Date? { data.flatMap { try? Date($0.generatedAt, strategy: .iso8601) } }
    var isStale: Bool { updatedAt.map { Date().timeIntervalSince($0) > 3 * 3600 } ?? false }

    /// Plain-language reason and what to do next, instead of a system error.
    static func explain(_ error: Error, haveData: Bool) -> String {
        let saved = haveData ? " Showing the last rankings you downloaded." : ""
        switch (error as? URLError)?.code {
        case .notConnectedToInternet?, .networkConnectionLost?, .dataNotAllowed?:
            return "You're offline.\(saved) Pull down to try again when you're connected."
        case .timedOut?:
            return "The rankings server is taking too long to answer.\(saved) Pull down to try again."
        case .some:
            return "Couldn't reach the rankings server.\(saved) Pull down to try again."
        case nil:
            return "The rankings data couldn't be read.\(saved) Try again in a few minutes."
        }
    }

    /// Live-period results followed by the older history, newest first.
    var allResults: [Match] {
        guard let data else { return [] }
        guard !history.isEmpty else { return data.results }
        let recent = Set(data.results.map(\.id))
        return data.results + history.filter { !recent.contains($0.id) }
    }

    /// Fetches history.json at most every few hours (it changes about daily).
    func loadHistory() async {
        if let loaded = historyLoadedAt, Date().timeIntervalSince(loaded) < 6 * 3600 { return }
        let cache = URL.cachesDirectory.appending(path: "history.json")
        if history.isEmpty, let bytes = try? Data(contentsOf: cache),
           let cached = try? JSONDecoder().decode(HistoryData.self, from: bytes) {
            history = cached.results
            historyFrom = cached.from
        }
        guard let url = Config.historyURL else { return }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (bytes, _) = try await URLSession.shared.data(for: request)
            let fresh = try JSONDecoder().decode(HistoryData.self, from: bytes)
            try? bytes.write(to: cache)
            history = fresh.results
            historyFrom = fresh.from
            historyLoadedAt = Date()
            historyFailed = false
        } catch {
            // keep whatever we had; the recent results still work
            historyFailed = history.isEmpty
        }
    }

    func confed(of code: String) -> String? { confedByCode[code] }

    func team(code: String) -> Team? { data?.teams.first { $0.code == code } }

    private func apply(_ new: RankingData, snapshot: Bool) {
        base = new
        // Drop live scores for matches the server has now caught up with.
        let pending = LiveScores.candidates(new)
        live = live.filter { pending.contains($0.key) }
        data = LiveScores.apply(live, to: new)
        isSnapshot = snapshot
        confedByCode = Dictionary(uniqueKeysWithValues: new.teams.map { ($0.code, $0.confed) })
    }

    private static func readLocal() -> (data: RankingData, bundled: Bool)? {
        let decoder = JSONDecoder()
        if let bytes = try? Data(contentsOf: cacheURL),
           let cached = try? decoder.decode(RankingData.self, from: bytes) {
            return (cached, false)
        }
        if let url = Bundle.main.url(forResource: "rankings", withExtension: "json"),
           let bytes = try? Data(contentsOf: url),
           let bundled = try? decoder.decode(RankingData.self, from: bytes) {
            return (bundled, true)
        }
        return nil
    }
}
