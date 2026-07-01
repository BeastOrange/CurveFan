import SwiftUI

/// Pure temperature formatting and color helper.
struct TempFormatter {
    func format(_ value: Double, useFahrenheit: Bool) -> String {
        let v = useFahrenheit ? value * 9 / 5 + 32 : value
        return String(format: "%.0f°%@", v, useFahrenheit ? "F" : "C")
    }

    func color(for value: Double) -> Color {
        if value < 50 { return .green }
        if value < 80 { return .orange }
        return .red
    }
}
