import Foundation

struct RankingData: Codable, Sendable {
    let generatedAt: String
    let official: Official
    let matchesSince: String
    let teams: [Team]
    let results: [Match]
    let fixtures: [Match]
    let competitions: [CompetitionInfo]?

    struct Official: Codable, Sendable {
        let pubDate: String
        let nextPubDate: String?
    }
}

/// One entry in the Competition filter: every competition that counts
/// towards the ranking, with how many results and fixtures it has now.
struct CompetitionInfo: Codable, Sendable, Identifiable, Hashable {
    let name: String
    let group: String
    let weight: String
    let results: Int
    let fixtures: Int
    var id: String { name }
}

struct Team: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let code: String
    let name: String
    let confed: String
    let officialRank: Int
    let officialPoints: Double
    let liveRank: Int
    let livePoints: Double
    let pointsChange: Double
    let rankChange: Int
}

struct Match: Codable, Sendable, Identifiable, Hashable {
    let kickoff: String
    let date: String
    let home: String
    let away: String
    let homeName: String
    let awayName: String
    let homeScore: Int?
    let awayScore: Int?
    let homePens: Int?
    let awayPens: Int?
    let status: Int
    let competition: String
    let stage: String
    let city: String
    let counted: Bool?
    let importance: Int?
    let homeDelta: Double?
    let awayDelta: Double?
    let note: String?
    let knockout: Bool?
    let expectedHome: Double?
    let prediction: Prediction?

    /// Points each side would gain or lose for each result ("win", "draw",
    /// "loss", and "pensWin"/"pensLoss" for knockout ties).
    struct Prediction: Codable, Sendable, Hashable {
        let home: [String: Double]
        let away: [String: Double]
    }

    var id: String { "\(kickoff)-\(home)-\(away)" }
    var isLive: Bool { status == 3 }
    var isCounted: Bool { counted ?? false }
    var kickoffDate: Date? { try? Date(kickoff, strategy: .iso8601) }
    var day: Date? { try? Date("\(date)T12:00:00Z", strategy: .iso8601) }

    var scoreText: String {
        guard let homeScore, let awayScore else { return "v" }
        if let homePens, let awayPens { return "\(homeScore)–\(awayScore) (\(homePens)–\(awayPens)p)" }
        return "\(homeScore)–\(awayScore)"
    }

    var stageText: String? {
        stage.isEmpty || stage.hasPrefix("Friendlies") ? nil : stage
    }

    func involves(_ code: String) -> Bool { home == code || away == code }
    func delta(for code: String) -> Double? { home == code ? homeDelta : awayDelta }
}

enum Confederation: String, CaseIterable, Identifiable {
    case all = "All", favourites = "★ Favourites", uefa = "UEFA", conmebol = "CONMEBOL", concacaf = "CONCACAF",
         caf = "CAF", afc = "AFC", ofc = "OFC"
    var id: String { rawValue }
}

extension Confederation {
    func includes(_ code: String, confed: String?, favourites: Set<String>) -> Bool {
        switch self {
        case .all: true
        case .favourites: favourites.contains(code)
        default: confed == rawValue
        }
    }
}
