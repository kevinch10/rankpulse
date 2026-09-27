import SwiftUI
import WidgetKit

@main
struct RankingsWidgetBundle: WidgetBundle {
    var body: some Widget {
        FavouritesWidget()
    }
}

struct FavouritesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FavouritesWidget", provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("My teams")
        .description("Live rank, points change and next match for your favourite teams. Shows the top 3 until you pick favourites in the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Data

struct WidgetTeam: Identifiable {
    let team: Team
    let flag: UIImage?
    let next: Match?
    let isFavourite: Bool
    var id: String { team.code }
}

struct Entry: TimelineEntry {
    let date: Date
    let teams: [WidgetTeam]
    let favourites: Bool   // false = showing the top of the table instead
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, teams: [], favourites: false)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (Entry) -> Void) {
        Task { completion(await Self.makeEntry(max: 3)) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<Entry>) -> Void) {
        let count = context.family == .systemSmall || context.family.isAccessory ? 1 : 3
        Task {
            let entry = await Self.makeEntry(max: count)
            // The data behind this updates hourly on the website.
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
        }
    }

    static func makeEntry(max: Int) async -> Entry {
        guard let data = await loadData() else { return Entry(date: .now, teams: [], favourites: false) }
        let favs = SharedStore.favourites
        var teams = favs.compactMap { code in data.teams.first { $0.code == code } }.sorted { $0.liveRank < $1.liveRank }
        let isFavourites = !teams.isEmpty
        // Fill any spare rows with the top of the table.
        for team in data.teams where teams.count < max && !favs.contains(team.code) { teams.append(team) }
        teams = Array(teams.prefix(max))

        var out: [WidgetTeam] = []
        for team in teams {
            let next = data.fixtures.first { $0.involves(team.code) }
            out.append(WidgetTeam(team: team, flag: await flag(team.code), next: next, isFavourite: favs.contains(team.code)))
        }
        return Entry(date: .now, teams: out, favourites: isFavourites)
    }

    /// Latest rankings from the website, falling back to the last copy.
    static func loadData() async -> RankingData? {
        let cache = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appending(path: "widget-rankings.json")
        if let url = Config.dataURL,
           let (bytes, _) = try? await URLSession.shared.data(from: url),
           let fresh = try? JSONDecoder().decode(RankingData.self, from: bytes) {
            if let cache { try? bytes.write(to: cache) }
            return fresh
        }
        if let cache, let bytes = try? Data(contentsOf: cache) {
            return try? JSONDecoder().decode(RankingData.self, from: bytes)
        }
        return nil
    }

    /// Widgets can't load images lazily, so fetch flags up front.
    static func flag(_ code: String) async -> UIImage? {
        guard let url = Config.flagURL(code), let (bytes, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: bytes)
    }
}

extension WidgetFamily {
    var isAccessory: Bool { self == .accessoryRectangular || self == .accessoryInline || self == .accessoryCircular }
}

// MARK: - Views

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallView(entry: entry)
            case .accessoryRectangular: RectangularView(entry: entry)
            case .accessoryInline: InlineView(entry: entry)
            default: MediumView(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            if family.isAccessory {
                Color.clear
            } else {
                ZStack {
                    Theme.night
                    Circle().fill(Theme.magenta).frame(width: 160).blur(radius: 50).offset(x: -90, y: -70).opacity(0.55)
                    Circle().fill(Theme.cyan).frame(width: 150).blur(radius: 50).offset(x: 110, y: -60).opacity(0.45)
                    Circle().fill(Theme.violet).frame(width: 150).blur(radius: 50).offset(x: 90, y: 90).opacity(0.5)
                }
            }
        }
    }
}

private struct Header: View {
    let entry: Entry

    var body: some View {
        HStack(spacing: 6) {
            Capsule().fill(Theme.spectrum).frame(width: 16, height: 5)
            Text(entry.favourites ? "MY TEAMS" : "TOP OF THE TABLE").font(.system(size: 10, weight: .heavy)).tracking(0.8)
            Spacer()
        }
        .foregroundStyle(.white.opacity(0.85))
    }
}

private struct FlagImage: View {
    let image: UIImage?
    var width: CGFloat = 22

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() } else { Color.white.opacity(0.2) }
        }
        .frame(width: width, height: width * 2 / 3)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

private struct Move: View {
    let change: Int

    var body: some View {
        if change != 0 {
            HStack(spacing: 1) {
                Image(systemName: change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").imageScale(.small)
                Text("\(abs(change))")
            }
            .foregroundStyle(change > 0 ? Color(hex: 0x2EE88A) : Color(hex: 0xFF5A6E))
        }
    }
}

private func nextLine(_ m: Match?, for code: String) -> String? {
    guard let m else { return nil }
    let opponent = m.home == code ? m.away : m.home
    let day = m.kickoffDate?.formatted(.dateTime.weekday(.abbreviated).day()) ?? m.date
    return "Next: v \(opponent) · \(day)"
}

struct SmallView: View {
    let entry: Entry

    var body: some View {
        if let t = entry.teams.first {
            VStack(alignment: .leading, spacing: 6) {
                Header(entry: entry)
                HStack(spacing: 6) {
                    FlagImage(image: t.flag, width: 24)
                    Text(t.team.name).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("#\(t.team.liveRank)").font(Theme.display(30))
                    Move(change: t.team.rankChange).font(.caption.weight(.bold))
                }
                Text("\(t.team.pointsChange.signed) pts")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(t.team.pointsChange >= 0 ? Color(hex: 0x2EE88A) : Color(hex: 0xFF5A6E))
                if let line = nextLine(t.next, for: t.team.code) {
                    Text(line).font(.caption2).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text("Open the app to load rankings").font(.caption).foregroundStyle(.white)
        }
    }
}

struct MediumView: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Header(entry: entry)
            ForEach(entry.teams) { t in
                HStack(spacing: 8) {
                    Text("\(t.team.liveRank)")
                        .font(Theme.display(13).monospacedDigit())
                        .frame(minWidth: 30, minHeight: 22)
                        .background(.white.opacity(0.15), in: .rect(cornerRadius: 6))
                    FlagImage(image: t.flag)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 3) {
                            Text(t.team.name).font(.caption.weight(.bold)).lineLimit(1)
                            if t.isFavourite && entry.teams.contains(where: { !$0.isFavourite }) {
                                Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(Theme.yellow)
                            }
                        }
                        if let line = nextLine(t.next, for: t.team.code) {
                            Text(line).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(t.team.livePoints.formatted(.number.precision(.fractionLength(0))))
                            .font(.caption.monospacedDigit().weight(.semibold))
                        HStack(spacing: 4) {
                            Move(change: t.team.rankChange)
                            Text(t.team.pointsChange.signedShort)
                                .foregroundStyle(t.team.pointsChange >= 0 ? Color(hex: 0x2EE88A) : Color(hex: 0xFF5A6E))
                        }
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                    }
                }
            }
            if entry.teams.isEmpty {
                Text("Open the app to load rankings").font(.caption)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }
}

struct RectangularView: View {
    let entry: Entry

    var body: some View {
        if let t = entry.teams.first {
            VStack(alignment: .leading, spacing: 1) {
                Text(t.team.name).font(.headline).lineLimit(1)
                HStack(spacing: 4) {
                    Text("#\(t.team.liveRank)").font(.title3.weight(.bold))
                    Move(change: t.team.rankChange).font(.caption)
                    Text("\(t.team.pointsChange.signedShort) pts").font(.caption)
                }
                if let line = nextLine(t.next, for: t.team.code) {
                    Text(line).font(.caption2).lineLimit(1)
                }
            }
        }
    }
}

struct InlineView: View {
    let entry: Entry

    var body: some View {
        if let t = entry.teams.first {
            Text("\(t.team.code) #\(t.team.liveRank) · \(t.team.pointsChange.signedShort) pts")
        }
    }
}
