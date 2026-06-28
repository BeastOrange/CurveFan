import SwiftUI

struct StatusChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

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

func cardStroke(radius: CGFloat, tint: Color = Color.white.opacity(0.09)) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
        .strokeBorder(tint, lineWidth: 1)
}

private extension NumberFormatter {
    static let rpm: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
