import SwiftUI
import CurveFanCore

struct HelperStatusBadge: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? .green : .red)
                .frame(width: 8, height: 8)
            Text(isConnected ? "Connected" : "Offline")
                .font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.regularMaterial, in: Capsule())
        .help(isConnected ? "Helper is connected" : "Helper is offline")
    }
}

struct NativeMetricTable: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider() }
                LabeledContent(row.0) {
                    Text(row.1)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct PresetButton: View {
    let preset: Preset
    let isSelected: Bool
    let maxRPM: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(preset.name)
                        .font(.headline)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.callout.weight(.semibold))
                    }
                }
                Text(presetRPMText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? .accentColor : .secondary)
    }

    private var presetRPMText: String {
        guard let curve = preset.fanToCurve[0], let first = curve.points.first, let last = curve.points.last else {
            return "System"
        }
        let low = first.rpm == 0 ? Int(maxRPM * 0.25) : first.rpm
        return "\(formatRPM(Double(low)))-\(formatRPM(Double(last.rpm))) RPM"
    }
}

struct PreferencesGroup: View {
    @ObservedObject var state: AppState

    var body: some View {
        GroupBox {
            Form {
                Picker("Temperature unit", selection: $state.useFahrenheit) {
                    Text("Celsius").tag(false)
                    Text("Fahrenheit").tag(true)
                }
                .pickerStyle(.segmented)

                Picker("Polling interval", selection: $state.pollingInterval) {
                    Text("1 sec").tag(1.0)
                    Text("2 sec").tag(2.0)
                    Text("5 sec").tag(5.0)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 132)
        } label: {
            Label("Preferences", systemImage: "gearshape")
        }
    }
}

struct RPMTrendChart: View {
    let samples: [RPMHistorySample]
    let currentRPM: Double?
    let minRPM: Double
    let maxRPM: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                chartGrid(in: proxy.size)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                chartLine(in: proxy.size)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                chartDots(in: proxy.size)
                chartLabels
            }
        }
        .accessibilityLabel("RPM history")
    }

    private var values: [Double] {
        let history = samples.map(\.rpm)
        if history.count >= 2 { return history }
        let rpm = currentRPM ?? minRPM
        return [rpm, rpm, rpm, rpm]
    }

    private var chartLabels: some View {
        VStack(alignment: .trailing, spacing: 28) {
            Text(formatRPM(maxRPM))
            Text(formatRPM((minRPM + maxRPM) / 2))
            Text(formatRPM(minRPM))
        }
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.trailing, 4)
    }

    private func chartGrid(in size: CGSize) -> Path {
        var path = Path()
        for fraction in [0.18, 0.5, 0.82] {
            let y = size.height * fraction
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width - 70, y: y))
        }
        return path
    }

    private func chartLine(in size: CGSize) -> Path {
        var path = Path()
        let points = mappedPoints(in: size)
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    @ViewBuilder
    private func chartDots(in size: CGSize) -> some View {
        ForEach(Array(mappedPoints(in: size).enumerated()), id: \.offset) { _, point in
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .position(point)
        }
    }

    private func mappedPoints(in size: CGSize) -> [CGPoint] {
        let width = max(size.width - 92, 1)
        let height = max(size.height - 42, 1)
        let denominator = max(Double(values.count - 1), 1)
        return values.enumerated().map { index, value in
            let x = Double(index) / denominator * width
            let yRatio = 1 - ((value - minRPM) / max(maxRPM - minRPM, 1))
            let y = 16 + min(max(yRatio, 0), 1) * height
            return CGPoint(x: x, y: y)
        }
    }
}
