import Foundation
import Observation

@MainActor
@Observable
final class RankingStore {
    private(set) var data: RankingData?
    private(set) var error: String?
    private(set) var isLoading = false
    private(set) var isSnapshot = false

    private var confedByCode: [String: String] = [:]
    let favourites = Favourites()
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
        } catch {
            self.error = data == nil ? error.localizedDescription : "Offline — showing saved data"
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
