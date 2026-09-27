import Foundation

enum Config {
    /// The published data file from the RankPulse website (refreshed every 2 hours
    /// by GitHub Actions). Until it's set, the app uses its bundled snapshot.
    static let dataURL: URL? = nil

    static func flagURL(_ code: String) -> URL? {
        URL(string: "https://api.fifa.com/api/v3/picture/flags-sq-2/\(code)")
    }
}
