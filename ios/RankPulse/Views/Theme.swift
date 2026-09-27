import SwiftUI

enum Theme {
    static let magenta = Color(hex: 0xFF2D75)
    static let orange = Color(hex: 0xFF8A00)
    static let yellow = Color(hex: 0xFFCC00)
    static let green = Color(hex: 0x12C26B)
    static let cyan = Color(hex: 0x00B3FF)
    static let violet = Color(hex: 0x6D5CFF)
    static let night = Color(hex: 0x0B0B1F)

    static let spectrum = LinearGradient(colors: [magenta, orange, yellow, green, cyan, violet],
                                         startPoint: .leading, endPoint: .trailing)

    /// Gradients for the four "movers" cards.
    static let cardGradients: [LinearGradient] = [
        (Color(hex: 0xFF8A00), Color(hex: 0xFF2D75)),
        (Color(hex: 0x0FA85C), Color(hex: 0x008F9E)),
        (Color(hex: 0xFF3B5C), Color(hex: 0x8B2CF6)),
        (Color(hex: 0x0096E0), Color(hex: 0x6D5CFF)),
    ].map { LinearGradient(colors: [$0.0, $0.1], startPoint: .topLeading, endPoint: .bottomTrailing) }

    static func confedColor(_ confed: String?) -> Color {
        switch confed {
        case "UEFA": Color(hex: 0x3B5BFF)
        case "CONMEBOL": Color(hex: 0xE0A800)
        case "CONCACAF": Color(hex: 0xFF3B5C)
        case "CAF": Color(hex: 0xFF7A00)
        case "AFC": Color(hex: 0x00A88F)
        case "OFC": Color(hex: 0x8B5CF6)
        default: violet
        }
    }

    static func medal(_ rank: Int) -> LinearGradient? {
        let pair: (UInt32, UInt32)? = switch rank {
        case 1: (0xFFD84D, 0xF5A300)
        case 2: (0xEEF1F6, 0xB7C0CC)
        case 3: (0xF3B37A, 0xC8702E)
        default: nil
        }
        return pair.map { LinearGradient(colors: [Color(hex: $0.0), Color(hex: $0.1)], startPoint: .topLeading, endPoint: .bottomTrailing) }
    }

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default).width(.expanded)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Dark hero banner with glowing colour blobs and the spectrum stripe.
struct HeroHeader: View {
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // One Text so both lines scale together.
            (Text("WORLD").foregroundStyle(Theme.spectrum) + Text(" FOOTBALL\nRANKINGS").foregroundStyle(.white))
                .font(Theme.display(28))
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("World Football Rankings")
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    PulseDot()
                    Text("LIVE").font(Theme.display(13))
                }
                .foregroundStyle(Theme.night)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.white, in: .capsule)
                Text("UNOFFICIAL")
                    .font(.caption2.weight(.bold)).tracking(1)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.4)))
            }
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .padding(.bottom, 6)
        .background {
            ZStack {
                Theme.night
                Circle().fill(Theme.magenta).frame(width: 220).blur(radius: 60).offset(x: -140, y: -90).opacity(0.6)
                Circle().fill(Theme.cyan).frame(width: 200).blur(radius: 60).offset(x: 130, y: -80).opacity(0.55)
                Circle().fill(Theme.violet).frame(width: 200).blur(radius: 60).offset(x: 150, y: 110).opacity(0.55)
                Circle().fill(Theme.yellow).frame(width: 160).blur(radius: 60).offset(x: -20, y: 130).opacity(0.3)
            }
        }
        .overlay(alignment: .bottom) { Theme.spectrum.frame(height: 5) }
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

struct PulseDot: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle().fill(Theme.magenta)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(Theme.magenta, lineWidth: 2).scaleEffect(on ? 2.4 : 1).opacity(on ? 0 : 0.8))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true }
            }
    }
}

struct ConfedPill: View {
    let confed: String

    var body: some View {
        Text(confed)
            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .lineLimit(1)
            .fixedSize()
            .background(Theme.confedColor(confed), in: .capsule)
    }
}
