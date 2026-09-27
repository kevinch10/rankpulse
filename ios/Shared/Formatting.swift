import SwiftUI

extension Double {
    var signed: String { (self > 0 ? "+" : "") + formatted(.number.precision(.fractionLength(2))) }
    var signedShort: String { (self > 0 ? "+" : "") + formatted(.number.precision(.fractionLength(1))) }
    var tone: Color { self > 0 ? Color(hex: 0x0FAE5C) : self < 0 ? Color(hex: 0xE5283F) : .secondary }
}
