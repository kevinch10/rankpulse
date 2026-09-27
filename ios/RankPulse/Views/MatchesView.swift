import SwiftUI

struct MatchesView: View {
    enum Kind { case results, fixtures }

    @Environment(RankingStore.self) private var store
    let kind: Kind
    @State private var search = ""
    @State private var confed = Confederation.all
    @State private var competition = ""
    @State private var day: Date?
    @State private var showCalendar = false

    var body: some View {
        NavigationStack {
            Group {
                if let data = store.data {
                    list(kind == .results ? data.results : data.fixtures)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(kind == .results ? "Results" : "Fixtures")
            .toolbar {
                ToolbarItemGroup {
                    Button { showCalendar = true } label: {
                        Image(systemName: day == nil ? "calendar" : "calendar.badge.checkmark")
                    }
                    .accessibilityLabel("Filter by date")
                    competitionMenu
                    ConfedMenu(selection: $confed)
                }
            }
            .sheet(isPresented: $showCalendar) {
                DayPickerSheet(day: $day, available: availableDays)
                    .presentationDetents([.medium, .large])
            }
            .safeAreaInset(edge: .top) {
                if let day {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                        Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("Show all dates") { self.day = nil }
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.magenta, in: .capsule)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }
            }
            .searchable(text: $search, prompt: "Search team")
            .refreshable { await store.refresh() }
            .navigationDestination(for: Team.self) { TeamDetailView(team: $0) }
        }
    }

    private var allMatches: [Match] {
        guard let data = store.data else { return [] }
        return kind == .results ? data.results : data.fixtures
    }

    /// The match days in this tab, as local dates, for the calendar.
    private var availableDays: [Date] {
        Array(Set(allMatches.compactMap { Self.localDate($0.date) })).sorted()
    }

    static func localDate(_ ymd: String) -> Date? {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func ymd(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private var competitionMenu: some View {
        let comps = Array(Set(allMatches.map(\.competition))).sorted()
        return Menu {
            Picker("Competition", selection: $competition) {
                Text("All competitions").tag("")
                ForEach(comps, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            Image(systemName: competition.isEmpty ? "trophy" : "trophy.fill")
        }
        .accessibilityLabel("Competition")
    }

    private func visible(_ m: Match) -> Bool {
        let favs = store.favourites.codes
        let confedOK = confed.includes(m.home, confed: store.confed(of: m.home), favourites: favs)
            || confed.includes(m.away, confed: store.confed(of: m.away), favourites: favs)
        let compOK = competition.isEmpty || m.competition == competition
        let dayOK = day.map { Self.ymd($0) == m.date } ?? true
        let searchOK = search.isEmpty || [m.homeName, m.awayName, m.home, m.away]
            .contains { $0.localizedCaseInsensitiveContains(search) }
        return confedOK && compOK && dayOK && searchOK
    }

    private func list(_ matches: [Match]) -> some View {
        let shown = matches.filter(visible)
        let days = Dictionary(grouping: shown, by: \.date)
        let order = days.keys.sorted(by: kind == .results ? (>) : (<))
        return List {
            ForEach(order, id: \.self) { day in
                Section {
                    ForEach(days[day] ?? []) { m in
                        let row = VStack(spacing: 8) {
                            MatchRow(match: m, fixture: kind == .fixtures)
                            if kind == .fixtures { PredictionView(match: m) }
                        }
                        if let team = store.team(code: m.home) {
                            NavigationLink(value: team) { row }
                        } else {
                            row
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        Capsule().fill(Theme.spectrum).frame(width: 18, height: 6)
                        Text(dayTitle(days[day]?.first).uppercased())
                            .font(Theme.display(15))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text((days[day]?.count ?? 0) == 1 ? "1 match" : "\(days[day]?.count ?? 0) matches").font(.caption).monospacedDigit()
                    }
                }
            }
        }
        .overlay {
            if shown.isEmpty {
                ContentUnavailableView(search.isEmpty ? (day == nil ? "No matches" : "No matches on this day") : "No results for “\(search)”",
                                       systemImage: day == nil ? "sportscourt" : "calendar")
            }
        }
    }

    private func dayTitle(_ m: Match?) -> String {
        guard let m, let d = m.day else { return m?.date ?? "" }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// Calendar sheet for picking a single match day. Days without matches are
/// outside the selectable range or simply show nothing.
struct DayPickerSheet: View {
    @Binding var day: Date?
    let available: [Date]
    @Environment(\.dismiss) private var dismiss
    @State private var selection = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let first = available.first, let last = available.last {
                    DatePicker("Match day", selection: $selection, in: first...last, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Theme.magenta)
                    let count = available.contains { Calendar.current.isDate($0, inSameDayAs: selection) }
                    Text(count ? "Matches on this day" : "No matches on this day")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("No match days", systemImage: "calendar")
                }
            }
            .padding(.horizontal)
            .navigationTitle("Pick a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("All dates") { day = nil; dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show") { day = selection; dismiss() }.bold()
                }
            }
            .onAppear {
                let today = Calendar.current.startOfDay(for: Date())
                selection = day ?? available.first { $0 >= today } ?? available.last ?? today
            }
        }
    }
}
