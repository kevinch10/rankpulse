import Foundation

/// A score straight from FIFA's live feed.
struct LiveScore: Sendable, Equatable {
    let status: Int
    let homeScore: Int?
    let awayScore: Int?
    let homePens: Int?
    let awayPens: Int?
}

/// Just the fields we read from FIFA's calendar API.
private struct FIFACalendar: Decodable {
    struct Item: Decodable {
        let IdMatch: String
        let MatchStatus: Int
        let HomeTeamScore: Int?
        let AwayTeamScore: Int?
        let HomeTeamPenaltyScore: Int?
        let AwayTeamPenaltyScore: Int?
    }
    let Results: [Item]?
    let ContinuationToken: String?
}

enum LiveScores {
    static let finished = 0, live = 3

    /// Matches worth asking FIFA about: live now, or due to start or finish soon.
    static func candidates(_ data: RankingData, now: Date = .now) -> Set<String> {
        let soon = { (m: Match) -> Bool in
            guard let k = m.kickoffDate else { return false }
            return k < now.addingTimeInterval(600) && k > now.addingTimeInterval(-4 * 3600)
        }
        let matches = data.results.filter { $0.status == live } + data.fixtures.filter(soon)
        return Set(matches.compactMap(\.fifaId))
    }

    static func fetch(_ wanted: Set<String>) async throws -> [String: LiveScore] {
        guard !wanted.isEmpty else { return [:] }
        let day = { (offset: Int) -> String in
            let d = Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: .now) ?? .now
            return String(d.ISO8601Format().prefix(10))
        }
        let base = "https://api.fifa.com/api/v3/calendar/matches?language=en&count=500&from=\(day(-1))T00:00:00Z&to=\(day(1))T23:59:59Z"
        var out: [String: LiveScore] = [:]
        var token: String?
        for _ in 0..<6 {
            var s = base
            if let token, let t = token.addingPercentEncoding(withAllowedCharacters: .alphanumerics) { s += "&continuationToken=\(t)" }
            guard let url = URL(string: s) else { break }
            let (bytes, _) = try await URLSession.shared.data(from: url)
            let page = try JSONDecoder().decode(FIFACalendar.self, from: bytes)
            for m in page.Results ?? [] where wanted.contains(m.IdMatch) {
                out[m.IdMatch] = LiveScore(status: m.MatchStatus, homeScore: m.HomeTeamScore, awayScore: m.AwayTeamScore,
                                           homePens: m.HomeTeamPenaltyScore, awayPens: m.AwayTeamPenaltyScore)
            }
            token = page.ContinuationToken
            if token == nil || (page.Results ?? []).isEmpty { break }
        }
        return out
    }

    /// Server data plus live scores. Matches that finished since the last
    /// server update are scored here with FIFA's formula, so the table moves
    /// at full time instead of at the next update.
    static func apply(_ live: [String: LiveScore], to base: RankingData) -> RankingData {
        guard !live.isEmpty else { return base }
        var data = base
        var results = base.results
        var fixtures: [Match] = []
        for f in base.fixtures {
            if let id = f.fifaId, let l = live[id], l.status == Self.live || l.status == finished {
                results.append(f)
            } else {
                fixtures.append(f)
            }
        }
        var points = Dictionary(uniqueKeysWithValues: base.teams.map { ($0.code, $0.livePoints) })
        var newlyFinished: [Int] = []
        for i in results.indices {
            guard let id = results[i].fifaId, let l = live[id] else { continue }
            results[i].status = l.status
            results[i].homeScore = l.homeScore
            results[i].awayScore = l.awayScore
            results[i].homePens = l.homePens
            results[i].awayPens = l.awayPens
            results[i].liveUpdated = true
            if l.status == finished && !(results[i].counted ?? false) && results[i].importance != nil { newlyFinished.append(i) }
        }
        newlyFinished.sort { results[$0].kickoff < results[$1].kickoff }
        let round2 = { (x: Double) in (x * 100).rounded() / 100 }
        for i in newlyFinished {
            let m = results[i]
            guard let ph = points[m.home], let pa = points[m.away], let hs = m.homeScore, let aws = m.awayScore,
                  let weight = m.importance else { continue }
            var wh = 0.5, wa = 0.5
            if hs != aws { wh = hs > aws ? 1 : 0; wa = 1 - wh }
            else if let hp = m.homePens, let ap = m.awayPens { (wh, wa) = hp > ap ? (0.75, 0.5) : (0.5, 0.75) }
            let (dh, da) = Formula.change(home: ph, away: pa, wHome: wh, wAway: wa, weight: weight, knockout: m.knockout == true)
            points[m.home] = ph + dh
            points[m.away] = pa + da
            results[i].counted = true
            results[i].homeDelta = dh
            results[i].awayDelta = da
            results[i].prediction = nil
        }
        var teams = base.teams
        for i in teams.indices {
            teams[i].livePoints = round2(points[teams[i].code] ?? teams[i].livePoints)
            teams[i].pointsChange = round2(teams[i].livePoints - teams[i].officialPoints)
        }
        teams.sort { $0.livePoints != $1.livePoints ? $0.livePoints > $1.livePoints : $0.officialRank < $1.officialRank }
        for i in teams.indices {
            teams[i].liveRank = i + 1
            teams[i].rankChange = teams[i].officialRank - teams[i].liveRank
        }
        data.teams = teams
        data.results = results.sorted { $0.kickoff > $1.kickoff }
        data.fixtures = fixtures
        return data
    }
}
