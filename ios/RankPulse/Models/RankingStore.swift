import Foundation
import Observation

@MainActor
@Observable
final class RankingStore {
    private(set) var data: RankingData?
    private(set) var error: String?
    private(set) var isLoading = false
    private(set) var isSnapshot = false
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
            error = nil
            await favourites.notifyChanges(in: fresh)
            await favourites.scheduleMatchReminders(fresh)
        } catch {
            self.error = data == nil ? error.localizedDescription : "Offline — showing saved data"
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
        } catch {
            // keep whatever we had; the recent results still work
        }
    }

    func confed(of code: String) -> String? { confedByCode[code] }

    func team(code: String) -> Team? { data?.teams.first { $0.code == code } }

    private func apply(_ new: RankingData, snapshot: Bool) {
        data = new
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
