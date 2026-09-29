import SwiftUI

/// Plain-language guide to what the numbers mean (reached from the ? button
/// and from "What do these numbers mean?" on match pages).
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let weights: [(String, String)] = [
        ("Friendly outside an international window", "5"),
        ("Friendly in a window, or a regional cup", "10"),
        ("Nations League (league phase and play-offs)", "15"),
        ("Nations League finals · World Cup and continental qualifiers", "25"),
        ("Continental finals (EURO, AFCON, Asian Cup…): before / from quarter-finals", "35 / 40"),
        ("World Cup finals: before / from quarter-finals", "50 / 60"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Official vs live") {
                    Text("FIFA publishes the official men's world ranking a few times a year. Between releases, this app takes the latest official points and adds every international result played since, using FIFA's own formula. That's the **live** rank. The **official** rank is the one FIFA last published.")
                }
                Section("How points change") {
                    Text("After each match, both teams gain or lose points depending on the result, how strong the opponent is, and how much the match counts (its **weight**). Beating a stronger team earns more; losing to a weaker one costs more. In knockout rounds of a final tournament, the losing team keeps its points.")
                }
                Section("Match weights") {
                    ForEach(weights, id: \.0) { row in
                        LabeledContent(row.0) { Text(row.1).monospacedDigit().fontWeight(.bold) }
                            .font(.subheadline)
                    }
                }
                Section("Points at stake") {
                    Text("For upcoming matches, the app shows what each team would gain or lose for a win, draw or loss, based on today's live points.")
                }
                Section("Where the data comes from") {
                    Text("Rankings, results and fixtures come from FIFA's public data, updated about every hour. A few competitions FIFA's feed doesn't carry (such as AFCON qualifiers) come from Wikipedia and a community results dataset. Rarely, FIFA changes a result after the match (for example a forfeit), so the live rank can differ slightly from the next official ranking.")
                }
                Section("Tips") {
                    Label("Search by everyday names: \"South Korea\", \"USA\" and \"Ivory Coast\" all work.", systemImage: "magnifyingglass")
                    Label("Swipe left on a team, or tap ★ on its page, to follow it.", systemImage: "star")
                    Label("Add the Football Rankings widget to your home screen; tap a team on it to open its page.", systemImage: "square.grid.2x2")
                    Label("Tap a match to see both teams and the points involved.", systemImage: "sportscourt")
                }
                Section {
                    Text("Not affiliated with FIFA.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("How it works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
