import StoreKit
import SwiftUI

/// FIFA's match multipliers run from 5 (friendly outside a window) to 60 (World Cup knockouts).
let fantasyMultipliers = Array(stride(from: 5, through: 60, by: 5))

/// Free users get one fantasy pairing per day (they can change its match type freely).
enum FantasyQuota {
    nonisolated(unsafe) private static let defaults = UserDefaults.standard  // UserDefaults is thread-safe
    private static var today: String { Date().formatted(.iso8601.year().month().day()) }
    static func key(_ a: String, _ b: String) -> String { [a, b].sorted().joined(separator: "-") }

    /// Today's free pairing, if one has been used.
    static var usedToday: String? {
        defaults.string(forKey: "fantasyDay") == today ? defaults.string(forKey: "fantasyPair") : nil
    }

    static func allows(_ pair: String, premium: Bool) -> Bool {
        premium || usedToday == nil || usedToday == pair
    }

    static func record(_ pair: String) {
        defaults.set(today, forKey: "fantasyDay")
        defaults.set(pair, forKey: "fantasyPair")
    }
}

struct FantasyView: View {
    @Environment(RankingStore.self) private var store
    @Environment(PremiumStore.self) private var premium
    @State private var teamA: Team?
    @State private var teamB: Team?
    @State private var multiplier = 10
    @State private var knockout = false
    @State private var shownPair: String?
    @State private var picking: Side?
    @State private var showPaywall = false
    @State private var usedToday = FantasyQuota.usedToday

    enum Side: String, Identifiable { case a, b; var id: String { rawValue } }

    private var pair: String? {
        guard let a = teamA, let b = teamB else { return nil }
        return FantasyQuota.key(a.code, b.code)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    teamButton(.a, teamA, placeholder: "Choose first team")
                    teamButton(.b, teamB, placeholder: "Choose second team")
                    Picker("Multiplier", selection: $multiplier) {
                        ForEach(fantasyMultipliers, id: \.self) { Text("×\($0)").tag($0) }
                    }
                    Toggle("Knockout", isOn: $knockout).tint(Theme.magenta)
                } header: {
                    Text("Pair up any two teams")
                } footer: {
                    Text(knockout
                         ? "Knockout: a draw goes to penalties, and the losing team keeps its points."
                         : "The multiplier is how much the match counts: friendlies are ×10, World Cup knockouts ×60.")
                }

                Section {
                    Button {
                        play()
                    } label: {
                        Label(buttonTitle, systemImage: needsPremium ? "crown.fill" : "wand.and.stars")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.bold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.magenta)
                    .disabled(pair == nil || pair == shownPair)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    quotaNote
                }

                if let a = teamA, let b = teamB, pair == shownPair {
                    FantasyResult(a: a, b: b, weight: multiplier, knockout: knockout, teams: store.data?.teams ?? [])
                }
            }
            .navigationTitle("Fantasy match")
            .sheet(item: $picking) { side in
                TeamPicker(exclude: side == .a ? teamB?.code : teamA?.code) { team in
                    if side == .a { teamA = team } else { teamB = team }
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .onAppear {
                usedToday = FantasyQuota.usedToday
                if teamA == nil, let code = store.favourites.codes.sorted().first { teamA = store.team(code: code) }
            }
        }
        .safeAreaInset(edge: .bottom) { BottomBannerAd() }
    }

    private var needsPremium: Bool {
        pair.map { !FantasyQuota.allows($0, premium: premium.isPremium) } ?? false
    }

    private var buttonTitle: String {
        if pair != nil && pair == shownPair { return "Showing this match" }
        return needsPremium ? "Unlock with Premium" : "Play fantasy match"
    }

    private func play() {
        guard let pair else { return }
        guard FantasyQuota.allows(pair, premium: premium.isPremium) else { showPaywall = true; return }
        if !premium.isPremium { FantasyQuota.record(pair) }
        usedToday = FantasyQuota.usedToday
        withAnimation { shownPair = pair }
    }

    @ViewBuilder private var quotaNote: some View {
        if premium.isPremium {
            Label("Premium · unlimited fantasy matches", systemImage: "crown.fill").foregroundStyle(Theme.orange)
        } else if let used = usedToday {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today's free match: \(pairNames(used)). Change its multiplier as often as you like; a new pairing is available tomorrow.")
                Button("Get unlimited matches and no ads with Premium") { showPaywall = true }.fontWeight(.semibold)
            }
        } else {
            Text("1 free fantasy match per day. Premium unlocks unlimited matches and removes all ads.")
        }
    }

    private func pairNames(_ key: String) -> String {
        key.split(separator: "-").map { store.team(code: String($0))?.name ?? String($0) }.joined(separator: " v ")
    }

    private func teamButton(_ side: Side, _ team: Team?, placeholder: String) -> some View {
        Button { picking = side } label: {
            HStack(spacing: 10) {
                if let team {
                    FlagView(code: team.code)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(team.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                        Text("#\(team.liveRank) · \(team.livePoints.formatted(.number.precision(.fractionLength(2)))) pts")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Theme.magenta)
                    Text(placeholder).foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
        }
        .onChange(of: team) { shownPair = nil }
    }
}

/// Points and new live rank for each team, for every possible result.
struct FantasyResult: View {
    let a: Team
    let b: Team
    let weight: Int
    let knockout: Bool
    let teams: [Team]

    private var outcomes: [(label: String, wa: Double, wb: Double)] {
        var list: [(String, Double, Double)] = [("\(a.name) win", 1, 0)]
        if knockout {
            list += [("\(a.name) win on penalties", 0.75, 0.5), ("\(b.name) win on penalties", 0.5, 0.75)]
        } else {
            list.append(("Draw", 0.5, 0.5))
        }
        list.append(("\(b.name) win", 0, 1))
        return list
    }

    var body: some View {
        ForEach(outcomes, id: \.label) { o in
            let d = Formula.change(home: a.livePoints, away: b.livePoints, wHome: o.wa, wAway: o.wb,
                                   weight: weight, knockout: knockout)
            let ranks = newRanks(a: a.livePoints + d.home, b: b.livePoints + d.away)
            Section(o.label) {
                row(a, d.home, ranks.a)
                row(b, d.away, ranks.b)
            }
        }
    }

    private func row(_ t: Team, _ delta: Double, _ rank: Int) -> some View {
        HStack(spacing: 10) {
            FlagView(code: t.code, width: 24)
            Text(t.name).lineLimit(1)
            Spacer()
            Text(delta.signed).monospacedDigit().fontWeight(.bold).foregroundStyle(delta.tone)
            let move = t.liveRank - rank
            HStack(spacing: 2) {
                Text("#\(t.liveRank) → #\(rank)").monospacedDigit()
                if move != 0 { RankMove(change: move) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(minWidth: 96, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// Live ranks after the fantasy result, with FIFA's tie-break on official rank.
    private func newRanks(a pa: Double, b pb: Double) -> (a: Int, b: Int) {
        let points = { (t: Team) in t.code == a.code ? pa : t.code == b.code ? pb : t.livePoints }
        let ahead = { (t: Team, p: Double, of: Team) in
            let q = points(t)
            return q > p || (q == p && t.officialRank < of.officialRank)
        }
        let rankA = 1 + teams.filter { $0.code != a.code && ahead($0, pa, a) }.count
        let rankB = 1 + teams.filter { $0.code != b.code && ahead($0, pb, b) }.count
        return (rankA, rankB)
    }
}

/// Searchable list of all teams.
struct TeamPicker: View {
    @Environment(RankingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let exclude: String?
    let pick: (Team) -> Void
    @State private var search = ""

    var body: some View {
        NavigationStack {
            let teams = (store.data?.teams ?? []).filter { $0.code != exclude && $0.matches(search) }
            List(teams) { team in
                Button {
                    pick(team)
                    dismiss()
                } label: {
                    TeamRow(team: team, isFavourite: store.favourites.contains(team.code))
                }
                .buttonStyle(.plain)
            }
            .overlay { if teams.isEmpty { ContentUnavailableView.search(text: search) } }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search team, e.g. Brazil or South Korea")
            .navigationTitle("Choose a team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Apple's subscription sheet for Premium.
struct PaywallView: View {
    @Environment(PremiumStore.self) private var premium
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if premium.productsAvailable == false {
            ContentUnavailableView {
                Label("Premium isn't available yet", systemImage: "crown")
            } description: {
                Text("Premium can't be bought on this device right now. The App Store isn't reachable, or subscriptions haven't been set up for this version of the app. Your free fantasy match resets tomorrow.")
            } actions: {
                Button("Close") { dismiss() }.buttonStyle(.borderedProminent).tint(Theme.magenta)
            }
        } else {
            store
        }
    }

    private var store: some View {
        SubscriptionStoreView(groupID: PremiumStore.groupID) {
            VStack(spacing: 12) {
                Image(systemName: "crown.fill").font(.system(size: 44)).foregroundStyle(Theme.spectrum)
                Text("Football Rankings Premium").font(Theme.display(22)).multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Unlimited fantasy matches every day", systemImage: "wand.and.stars")
                    Label("No ads anywhere in the app", systemImage: "nosign")
                    Label("Try any pairing, any multiplier", systemImage: "arrow.triangle.2.circlepath")
                    Label("1 week free, cancel anytime", systemImage: "checkmark.seal")
                }
                .font(.subheadline)
            }
            .padding()
        }
        .storeButton(.visible, for: .restorePurchases)
        .subscriptionStoreControlStyle(.prominentPicker)
        .tint(Theme.magenta)
        .onInAppPurchaseCompletion { _, _ in
            await premium.refresh()
            if premium.isPremium { dismiss() }
        }
    }
}
