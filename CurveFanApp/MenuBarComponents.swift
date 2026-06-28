import SwiftUI
import CurveFanCore

struct MenuHeaderCard: View {
    let rpm: Double?
    let minRPM: Double
    let maxRPM: Double
    let cpuText: String
    let gpuText: String
    let controlState: MenuControlState

    var body: some View {
        HStack(spacing: 14) {
            FanPulseView(rpm: rpm, maxRPM: maxRPM, tint: controlState.tint)
                .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(controlState.tint)
                        .frame(width: 8, height: 8)
                    Text(controlState.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(rpm.map { "\(formatRPM($0)) RPM" } ?? "-- RPM")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(controlState.detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    StatusChip(icon: "thermometer", text: "CPU \(cpuText)")
                    StatusChip(icon: "gauge.with.dots.needle.50percent", text: "\(formatRPM(minRPM))-\(formatRPM(maxRPM))")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(cardStroke(radius: 12))
        .accessibilityElement(children: .combine)
    }
}

struct FanPulseView: View {
    let rpm: Double?
    let maxRPM: Double
    let tint: Color
    @State private var angle = 0.0

    private var progress: Double {
        guard let rpm, maxRPM > 0 else { return 0 }
        return min(max(rpm / maxRPM, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.11))
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: 14)
                .scaleEffect(0.78 + progress * 0.18)
            Circle()
                .strokeBorder(tint.opacity(0.65), lineWidth: 2)

            ForEach(0..<5, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: 13, height: 38 + progress * 10)
                    .offset(y: -20)
                    .rotationEffect(.degrees(angle + Double(index) * 72))
                    .opacity(0.88)
            }

            Circle()
                .fill(.thickMaterial)
                .frame(width: 30, height: 30)
            Image(systemName: "fan.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        }
        .shadow(color: tint.opacity(0.22), radius: 14, y: 6)
        .onAppear {
            angle = 0
            withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                angle = 360
            }
        }
    }
}

struct QuickMetricGrid: View {
    let rpm: Double?
    let rangeText: String
    let cpuText: String
    let gpuText: String
    let pollingText: String

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                QuickMetric(title: "Current", value: rpm.map { formatRPM($0) } ?? "--", suffix: "RPM")
                QuickMetric(title: "Range", value: rangeText, suffix: "RPM")
            }
            GridRow {
                QuickMetric(title: "CPU", value: cpuText, suffix: "")
                QuickMetric(title: "GPU", value: gpuText, suffix: "Poll \(pollingText)")
            }
        }
    }
}

struct QuickMetric: View {
    let title: String
    let value: String
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.horizontal, 11)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
