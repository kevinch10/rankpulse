import SwiftUI

struct FlagView: View {
    let code: String
    var width: CGFloat = 28

    var body: some View {
        AsyncImage(url: Config.flagURL(code)) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.secondary.opacity(0.15)
        }
        .frame(width: width, height: width * 2 / 3)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityHidden(true)
    }
}

extension Double {
    var signed: String { (self > 0 ? "+" : "") + formatted(.number.precision(.fractionLength(2))) }
    var signedShort: String { (self > 0 ? "+" : "") + formatted(.number.precision(.fractionLength(1))) }
    var tone: Color { self > 0 ? .green : self < 0 ? .red : .secondary }
}

struct RankMove: View {
    let change: Int

    var body: some View {
        if change == 0 {
            Text("–").foregroundStyle(.secondary)
        } else {
            HStack(spacing: 2) {
                Image(systemName: change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .imageScale(.small)
                Text("\(abs(change))")
            }
            .foregroundStyle(change > 0 ? .green : .red)
            .accessibilityLabel(change > 0 ? "Up \(change)" : "Down \(-change)")
        }
    }
}

struct ConfedMenu: View {
    @Binding var selection: Confederation

    var body: some View {
        Menu {
            Picker("Confederation", selection: $selection) {
                ForEach(Confederation.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            Label(selection == .all ? "Confederation" : selection.rawValue,
                  systemImage: selection == .all ? "globe" : "globe.europe.africa.fill")
        }
    }
}

struct MatchRow: View {
    let match: Match
    var fixture = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                side(match.home, match.homeName, match.homeDelta, leading: true)
                Group {
                    if fixture, let date = match.kickoffDate {
                        Text(date, format: .dateTime.hour().minute())
                            .foregroundStyle(.secondary)
                    } else {
                        Text(match.scoreText)
                    }
                }
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .frame(minWidth: 52)
                side(match.away, match.awayName, match.awayDelta, leading: false)
            }
            HStack(spacing: 6) {
                if match.isLive {
                    Text("LIVE").font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.red, in: .rect(cornerRadius: 4))
                }
                Text([match.competition, match.stageText].compactMap { $0 }.joined(separator: " · "))
                if let i = match.importance { Text("I=\(i)").monospaced() }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func side(_ code: String, _ name: String, _ delta: Double?, leading: Bool) -> some View {
        HStack(spacing: 6) {
            if leading { FlagView(code: code, width: 22) }
            VStack(alignment: leading ? .leading : .trailing, spacing: 1) {
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                if let delta, match.isCounted {
                    Text(delta.signedShort).font(.caption2.monospaced()).foregroundStyle(delta.tone)
                }
            }
            if !leading { FlagView(code: code, width: 22) }
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }
}

struct StatusBanner: View {
    @Environment(RankingStore.self) private var store

    var body: some View {
        if let error = store.error {
            Label(error, systemImage: "wifi.slash").font(.footnote).foregroundStyle(.secondary)
        } else if store.isSnapshot {
            Label("Showing bundled data", systemImage: "shippingbox").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
