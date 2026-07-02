import SwiftUI
import CurveFanCore

struct FanDisplayRow: Identifiable {
    let id: Int
    let info: FanInfo
    let modeText: String
    let statusText: String
    let statusTint: Color

    var name: String { "Fan \(id + 1)" }
    var location: String { id == 0 ? "Primary exhaust" : "Auxiliary exhaust" }
    var rangeText: String { "\(formatRPM(info.minRPM))-\(formatRPM(info.maxRPM)) RPM" }
}

struct FansInventoryGroup: View {
    let rows: [FanDisplayRow]
    @Binding var selectedFanID: Int?

    var body: some View {
        CardView(title: "Fans", systemImage: "fan") {
            VStack(alignment: .leading, spacing: 0) {
                FanHeaderRow()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                Divider()

                if rows.isEmpty {
                    ContentUnavailableView(
                        "No fan data",
                        systemImage: "fan",
                        description: Text("Refresh helper connection to read SMC fan information.")
                    )
                    .frame(height: 170)
                } else {
                    List(selection: $selectedFanID) {
                        ForEach(rows) { row in
                            FanInventoryRow(row: row)
                                .tag(Optional(row.id))
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .frame(height: min(CGFloat(rows.count) * 74 + 12, 260))
                }
            }
        }
    }
}

private struct FanHeaderRow: View {
    var body: some View {
        HStack(spacing: 16) {
            Text("Fan").frame(minWidth: 260, alignment: .leading)
            Spacer()
            Text("Current").frame(width: 110, alignment: .trailing)
            Text("Range").frame(width: 150, alignment: .trailing)
            Text("Mode").frame(width: 140, alignment: .leading)
            Text("Status").frame(width: 110, alignment: .leading)
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct FanInventoryRow: View {
    let row: FanDisplayRow

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "fan.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name).font(.headline)
                    Text(row.location)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 260, alignment: .leading)

            Spacer()
            Text("\(formatRPM(row.info.actualRPM)) RPM")
                .font(.body.monospacedDigit())
                .frame(width: 110, alignment: .trailing)
            Text(row.rangeText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
            Label(row.modeText, systemImage: modeIcon)
                .font(.callout)
                .frame(width: 140, alignment: .leading)
            Label(row.statusText, systemImage: "circle.fill")
                .font(.callout)
                .foregroundStyle(row.statusTint)
                .frame(width: 110, alignment: .leading)
        }
        .padding(.vertical, 8)
    }

    private var modeIcon: String {
        row.modeText.hasPrefix("Curve") ? "point.topleft.down.curvedto.point.bottomright.up" :
            row.modeText == "Manual" ? "hand.raised" : "checkmark.circle"
    }
}

struct ManualFanControlGroup: View {
    @ObservedObject var state: AppState
    let rows: [FanDisplayRow]
    @Binding var selectedFanID: Int
    @Binding var targetRPM: Double
    let isConnected: Bool

    var body: some View {
        CardView(title: "Manual Control", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 16) {
                Form {
                    Picker("Fan", selection: $selectedFanID) {
                        ForEach(rows) { row in
                            Text(row.name).tag(row.id)
                        }
                    }
                    .disabled(rows.isEmpty)

                    LabeledContent("Target") {
                        Text("\(formatRPM(targetRPM)) RPM")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .frame(height: 94)

                Slider(value: $targetRPM, in: rpmRange, step: 100)
                    .disabled(rows.isEmpty)

                HStack {
                    Text("Min \(formatRPM(rpmRange.lowerBound)) RPM")
                    Spacer()
                    Text("Max \(formatRPM(rpmRange.upperBound)) RPM")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Restore System Auto") {
                        Task { await state.restoreAuto(fan: selectedFanID) }
                    }
                    Button("Apply Manual") {
                        Task { await state.setManualRPM(targetRPM, fan: selectedFanID) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .disabled(rows.isEmpty || !isConnected)
            }
        }
    }

    private var rpmRange: ClosedRange<Double> {
        guard let row = rows.first(where: { $0.id == selectedFanID }) else {
            return state.minRPM...state.maxRPM
        }
        return row.info.minRPM...row.info.maxRPM
    }
}

struct FanStatusGroup: View {
    @ObservedObject var state: AppState
    let selectedRow: FanDisplayRow?
    let isConnected: Bool

    var body: some View {
        FormCard(title: "Status", systemImage: "checklist") {
            LabeledContent("SMC sync") {
                Text(isConnected ? "Connected" : "Offline")
            }
            LabeledContent("Selected fan") {
                Text(selectedRow?.name ?? "--")
            }
            LabeledContent("Hardware mode") {
                Text(selectedRow.map { hardwareModeText($0.info.mode) } ?? "--")
            }
            LabeledContent("Temperature sensor") {
                Text(state.defaultSensorKey.isEmpty ? "Pending" : state.defaultSensorKey)
            }
            LabeledContent("Last refresh") {
                Text(lastRefreshText).monospacedDigit()
            }
        }
        .frame(minHeight: 178)
    }

    private var lastRefreshText: String {
        state.lastPollDate?.formatted(date: .omitted, time: .standard) ?? "--"
    }

    private func hardwareModeText(_ mode: FanMode) -> String {
        switch mode {
        case .auto: return "System Auto"
        case .manual: return "Manual"
        case .system: return "System"
        }
    }
}

struct CurveSummaryGroup: View {
    let preset: Preset?
    let curve: FanCurve?
    let minRPM: Double
    let maxRPM: Double

    var body: some View {
        CardView(title: "Control Curve", systemImage: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Active curve") {
                    Text(preset?.name ?? "System Auto")
                }

                if let curve, !curve.points.isEmpty {
                    CurvePointStrip(points: curve.points, minRPM: minRPM, maxRPM: maxRPM)
                } else {
                    Text("System Auto is active. macOS owns the fan curve.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct CurvePointStrip: View {
    let points: [CurvePoint]
    let minRPM: Double
    let maxRPM: Double

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                VStack(spacing: 6) {
                    Capsule()
                        .fill(point.rpm == 0 ? Color.secondary.opacity(0.35) : Color.accentColor.opacity(0.75))
                        .frame(width: 42, height: barHeight(for: point.rpm))
                    Text("\(Int(point.temperature))°")
                    Text(point.rpm == 0 ? "Auto" : formatRPM(Double(point.rpm)))
                }
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .frame(height: 148, alignment: .bottomLeading)
    }

    private func barHeight(for rpm: Int) -> CGFloat {
        guard rpm > 0 else { return 34 }
        let ratio = (Double(rpm) - minRPM) / max(maxRPM - minRPM, 1)
        return 34 + CGFloat(min(max(ratio, 0), 1)) * 78
    }
}
