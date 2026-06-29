import SwiftUI
import Charts
import CurveFanCore

struct PresetsView: View {
    @ObservedObject var state: AppState
    @State private var selectedPresetName = "Balanced"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    subtitle: "Native macOS preset management",
                    isConnected: isConnected
                )

                HStack(alignment: .top, spacing: 18) {
                    PresetLibraryGroup(
                        presets: state.presets,
                        selectedPresetName: $selectedPresetName,
                        activePresetName: state.activePreset?.name
                    )
                    .frame(minWidth: 300, maxWidth: 420)

                    PresetDetailGroup(
                        preset: selectedPreset,
                        state: state,
                        isConnected: isConnected
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
    }

    private var selectedPreset: Preset {
        state.presets.first { $0.name == selectedPresetName } ??
            state.presets.first { $0.name == "Balanced" } ??
            .auto
    }

    private var isConnected: Bool {
        if case .connected = state.connectionStatus { return true }
        return false
    }
}

private struct PresetLibraryGroup: View {
    let presets: [Preset]
    @Binding var selectedPresetName: String
    let activePresetName: String?

    var body: some View {
        GroupBox {
            List(selection: $selectedPresetName) {
                ForEach(presets, id: \.name) { preset in
                    PresetLibraryRow(
                        preset: preset,
                        isActive: activePresetName == preset.name ||
                            (activePresetName == nil && preset.name == "Auto")
                    )
                    .tag(preset.name)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 520)
        } label: {
            Label("Preset Library", systemImage: "slider.horizontal.3")
        }
    }
}

private struct PresetLibraryRow: View {
    let preset: Preset
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(String(preset.name.prefix(1)))
                .font(.headline)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(isActive ? 0.85 : 0.16), in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(isActive ? .white : .primary)

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name).font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(rangeText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 8)
    }

    private var description: String {
        switch preset.name {
        case "Auto": return "System controlled curve"
        case "Quiet": return "Lower fan noise for light work"
        case "Balanced": return "Recommended daily profile"
        case "MaxCool": return "Maximum thermal headroom"
        default: return "Custom fan curve"
        }
    }

    private var rangeText: String {
        guard let curve = preset.fanToCurve[0], !curve.points.isEmpty else {
            return "System Auto"
        }
        let rpms = curve.points.map(\.rpm).filter { $0 > 0 }
        guard let min = rpms.min(), let max = rpms.max() else { return "System Auto" }
        return "\(formatRPM(Double(min)))-\(formatRPM(Double(max))) RPM"
    }
}

private struct PresetDetailGroup: View {
    let preset: Preset
    @ObservedObject var state: AppState
    let isConnected: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(preset.name)
                        .font(.largeTitle.weight(.semibold))
                    Text(detail)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                NativeMetricTable(rows: [
                    ("Mode", preset.name == "Auto" ? "System" : "Curve"),
                    ("Fans", "\(state.knownFanCount)"),
                    ("Range", rangeText)
                ])

                CurvePreviewGroup(curve: preset.fanToCurve[0], minRPM: state.minRPM, maxRPM: state.maxRPM)

                NativeMetricTable(rows: [
                    ("Temperature units", state.useFahrenheit ? "Fahrenheit" : "Celsius"),
                    ("Polling interval", "\(Int(state.pollingInterval)) seconds"),
                    ("Fallback mode", "System Auto")
                ])

                HStack {
                    Spacer()
                    Button("Restore Auto") {
                        Task { await state.restoreAuto() }
                    }
                    Button(applyTitle) {
                        Task { await state.applyPreset(preset) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApply)
                }
            }
            .padding(6)
        } label: {
            Label("Preset Details", systemImage: "chart.xyaxis.line")
        }
    }

    private var detail: String {
        switch preset.name {
        case "Auto": return "macOS owns the fan controller."
        case "Quiet": return "A light curve for low-noise work."
        case "Balanced": return "Stable thermals without ramping early."
        case "MaxCool": return "Aggressive cooling for sustained load."
        default: return "Custom temperature response."
        }
    }

    private var rangeText: String {
        guard let curve = preset.fanToCurve[0], !curve.points.isEmpty else { return "System" }
        let rpms = curve.points.map(\.rpm).filter { $0 > 0 }
        guard let min = rpms.min(), let max = rpms.max() else { return "System" }
        return "\(formatRPM(Double(min)))-\(formatRPM(Double(max)))"
    }

    private var applyTitle: String {
        preset.name == "Auto" ? "Apply Auto" : "Apply \(preset.name)"
    }

    private var canApply: Bool {
        isConnected && (preset.name == "Auto" || !state.defaultSensorKey.isEmpty)
    }
}

private struct CurvePreviewGroup: View {
    let curve: FanCurve?
    let minRPM: Double
    let maxRPM: Double

    var body: some View {
        GroupBox {
            if let curve, !curve.points.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Temperature response - Celsius")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    CurvePreview(points: curve.points, minRPM: minRPM, maxRPM: maxRPM)
                        .frame(height: 170)
                }
                .padding(6)
            } else {
                Text("System Auto has no CurveFan curve preview.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        } label: {
            Label("Fan Curve Preview", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
        }
    }
}

private struct CurvePreview: View {
    let points: [CurvePoint]
    let minRPM: Double
    let maxRPM: Double

    var body: some View {
        Chart(points, id: \.temperature) { point in
            let rpm = point.rpm == 0 ? minRPM : Double(point.rpm)
            AreaMark(x: .value("Temp", point.temperature), y: .value("RPM", rpm))
                .opacity(0.12)
            LineMark(x: .value("Temp", point.temperature), y: .value("RPM", rpm))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Temp", point.temperature), y: .value("RPM", rpm))
                .symbolSize(30)
        }
        .chartYScale(domain: minRPM...maxRPM)
        .chartXAxisLabel("°C")
        .accessibilityLabel("Fan curve preview")
    }
}
