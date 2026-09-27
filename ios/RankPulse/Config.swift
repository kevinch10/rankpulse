import Foundation

enum Config {
    /// The published data file from the RankPulse website (refreshed every hour
    /// by GitHub Actions). If it can't be reached, the app uses its cached or bundled copy.
    static let dataURL: URL? = URL(string: "https://kevinch10.github.io/rankpulse/data/rankings.json")

    static func flagURL(_ code: String) -> URL? {
        URL(string: "https://api.fifa.com/api/v3/picture/flags-sq-2/\(code)")
    }
}
