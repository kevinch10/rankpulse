import Foundation

enum Config {
    /// The published data file from the World Football Rankings website
    /// (refreshed by GitHub Actions). If it can't be reached, the app uses its cached or bundled copy.
    static let dataURL: URL? = URL(string: "https://kevinch10.github.io/world-football-rankings/data/rankings.json")
    /// A year of older results, loaded when the Results tab first needs it.
    static let historyURL: URL? = URL(string: "https://kevinch10.github.io/world-football-rankings/data/history.json")

    /// AdMob ad units. These are Google's public TEST IDs — replace them (and
    /// GADApplicationIdentifier in RankPulse/Info.plist) with your own from
    /// admob.google.com before publishing, or ads won't earn anything.
    static let bannerAdUnitID = "ca-app-pub-3940256099942544/2435281174"
    static let inlineAdUnitID = "ca-app-pub-3940256099942544/2934735716"  // fixed-size banner test unit
    /// One in-list ad after every this many rows in Results and Fixtures.
    static let inlineAdEvery = 12

    static func flagURL(_ code: String) -> URL? {
        URL(string: "https://api.fifa.com/api/v3/picture/flags-sq-2/\(code)")
    }
}
