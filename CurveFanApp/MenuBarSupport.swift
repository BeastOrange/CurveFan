import SwiftUI

struct AlertBanner: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

func formatRPM(_ value: Double) -> String {
    NumberFormatter.rpm.string(from: NSNumber(value: Int(value))) ?? "\(Int(value))"
}

private extension NumberFormatter {
    static let rpm: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
