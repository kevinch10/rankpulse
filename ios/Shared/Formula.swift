import Foundation

/// FIFA's SUM formula: P = P_before + I × (W − W_e).
enum Formula {
    static func expected(_ team: Double, _ opponent: Double) -> Double {
        1 / (pow(10, -(team - opponent) / 600) + 1)
    }

    /// Points each side gains (+) or loses (−), rounded like FIFA's table.
    static func change(home: Double, away: Double, wHome: Double, wAway: Double,
                       weight: Int, knockout: Bool) -> (home: Double, away: Double) {
        var dh = Double(weight) * (wHome - expected(home, away))
        var da = Double(weight) * (wAway - expected(away, home))
        if knockout { dh = max(dh, 0); da = max(da, 0) }  // losers in a finals knockout tie keep their points
        return ((dh * 100).rounded() / 100, (da * 100).rounded() / 100)
    }
}
