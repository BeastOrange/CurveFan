import SwiftUI
import CurveFanCore

struct FansView: View {
    @ObservedObject var state: AppState
    @State private var selectedFanID: Int? = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    subtitle: "Fan hardware and override state",
                    isConnected: isConnected
                )

                FansInventoryGroup(rows: rows, selectedFanID: $selectedFanID)

                HStack(alignment: .top, spacing: 18) {
                    ManualFanControlGroup(
                        state: state,
                        rows: rows,
                        selectedFanID: selectedFanBinding,
                        targetRPM: targetRPMBinding,
                        isConnected: isConnected
                    )
                    .frame(maxWidth: .infinity)

                    FanStatusGroup(
                        state: state,
                        selectedRow: selectedRow,
                        isConnected: isConnected
                    )
                    .frame(width: 340)
                }

                CurveSummaryGroup(
                    preset: activeCurvePreset,
                    curve: selectedCurve,
                    minRPM: selectedRow?.info.minRPM ?? state.minRPM,
                    maxRPM: selectedRow?.info.maxRPM ?? state.maxRPM
                )
            }
            .padding(24)
            .frame(maxWidth: 1180, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var rows: [FanDisplayRow] {
        state.fanInfo.keys.sorted().compactMap { id in
            guard let info = state.fanInfo[id] else { return nil }
            return FanDisplayRow(
                id: id,
                info: info,
                modeText: modeText(fan: id, info: info),
                statusText: statusText(info),
                statusTint: statusTint(info)
            )
        }
    }

    private var selectedRow: FanDisplayRow? {
        rows.first { $0.id == selectedFanID } ?? rows.first
    }

    private var selectedFanBinding: Binding<Int> {
        Binding(
            get: { selectedRow?.id ?? rows.first?.id ?? 0 },
            set: { selectedFanID = $0 }
        )
    }

    private var targetRPMBinding: Binding<Double> {
        Binding(
            get: {
                guard let row = selectedRow else { return state.manualRPM }
                let target = state.manualRPM == 0 ? row.info.actualRPM : state.manualRPM
                return min(max(target, row.info.minRPM), row.info.maxRPM)
            },
            set: { state.manualRPM = $0 }
        )
    }

    private var activeCurvePreset: Preset? {
        guard let preset = state.activePreset, preset.name != "Auto" else { return nil }
        return preset
    }

    private var selectedCurve: FanCurve? {
        guard let fan = selectedRow?.id else { return nil }
        return activeCurvePreset?.fanToCurve[fan]
    }

    private var isConnected: Bool {
        if case .connected = state.connectionStatus { return true }
        return false
    }

    private func modeText(fan: Int, info: FanInfo) -> String {
        if state.manualFanIDs.contains(fan) { return "Manual" }
        if fan == 0, let preset = activeCurvePreset { return "Curve - \(preset.name)" }
        switch info.mode {
        case .auto: return "System Auto"
        case .manual: return "Manual"
        case .system: return "System"
        }
    }

    private func statusText(_ info: FanInfo) -> String {
        if info.actualRPM < info.minRPM * 0.9 { return "Below range" }
        if info.actualRPM > info.maxRPM * 1.05 { return "Above range" }
        return "Normal"
    }

    private func statusTint(_ info: FanInfo) -> Color {
        statusText(info) == "Normal" ? .green : .orange
    }
}
