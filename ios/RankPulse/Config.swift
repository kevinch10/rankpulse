import Foundation

enum Config {
    /// The published data file from the World Football Rankings website
    /// (refreshed by GitHub Actions). If it can't be reached, the app uses its cached or bundled copy.
    static let dataURL: URL? = URL(string: "https://kevinch10.github.io/rankpulse/data/rankings.json")
    /// A year of older results, loaded when the Results tab first needs it.
    static let historyURL: URL? = URL(string: "https://kevinch10.github.io/rankpulse/data/history.json")

    static func flagURL(_ code: String) -> URL? {
        URL(string: "https://api.fifa.com/api/v3/picture/flags-sq-2/\(code)")
    }
}
