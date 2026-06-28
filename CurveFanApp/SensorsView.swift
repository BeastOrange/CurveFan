import SwiftUI
import CurveFanCore

struct SensorsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    subtitle: "Active macOS SMC readings",
                    isConnected: isConnected
                )

                SensorSummaryGroup(
                    hottest: hottestText,
                    average: averageText,
                    unit: state.useFahrenheit ? "Fahrenheit" : "Celsius"
                )

                SensorReadingsGroup(rows: rows)
            }
            .padding(24)
            .frame(maxWidth: 1180, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var rows: [SensorDisplayRow] {
        let thermal = state.temperatures.sorted { lhs, rhs in
            if lhs.group == rhs.group { return lhs.name < rhs.name }
            return groupRank(lhs.group) < groupRank(rhs.group)
        }.map {
            SensorDisplayRow(
                name: $0.name,
                detail: "\($0.key) - \($0.group.rawValue)",
                value: state.formatTemp($0.value),
                icon: icon(for: $0.group)
            )
        }

        let fans = state.fanInfo.keys.sorted().compactMap { fan -> SensorDisplayRow? in
            guard let info = state.fanInfo[fan] else { return nil }
            return SensorDisplayRow(
                name: fan == 0 ? "System Fan Tach" : "Fan \(fan + 1) Tach",
                detail: "F\(fan)Ac - fan",
                value: "\(formatRPM(info.actualRPM)) RPM",
                icon: "fan"
            )
        }
        return thermal + fans
    }

    private var hottestText: String {
        guard let hottest = state.temperatures.map(\.value).max() else { return "--" }
        return state.formatTemp(hottest)
    }

    private var averageText: String {
        guard !state.temperatures.isEmpty else { return "--" }
        let total = state.temperatures.reduce(0) { $0 + $1.value }
        return state.formatTemp(total / Double(state.temperatures.count))
    }

    private var isConnected: Bool {
        if case .connected = state.connectionStatus { return true }
        return false
    }

    private func groupRank(_ group: SensorGroup) -> Int {
        switch group {
        case .cpu: return 0
        case .gpu: return 1
        case .memory: return 2
        case .system: return 3
        case .fan: return 4
        }
    }

    private func icon(for group: SensorGroup) -> String {
        switch group {
        case .cpu: return "cpu"
        case .gpu: return "display"
        case .memory: return "memorychip"
        case .system: return "thermometer"
        case .fan: return "fan"
        }
    }
}

private struct SensorDisplayRow: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let value: String
    let icon: String
}

private struct SensorSummaryGroup: View {
    let hottest: String
    let average: String
    let unit: String

    var body: some View {
        HStack(spacing: 18) {
            SensorSummaryItem(title: "Hottest", value: hottest, icon: "thermometer.high")
            SensorSummaryItem(title: "Average", value: average, icon: "gauge.with.dots.needle.50percent")
            SensorSummaryItem(title: "Unit", value: unit, icon: "ruler")
        }
    }
}

private struct SensorSummaryItem: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        GroupBox {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(title, systemImage: icon)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                }
                Spacer()
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 92)
        }
    }
}

private struct SensorReadingsGroup: View {
    let rows: [SensorDisplayRow]

    var body: some View {
        GroupBox {
            if rows.isEmpty {
                ContentUnavailableView(
                    "No sensor readings",
                    systemImage: "thermometer",
                    description: Text("Refresh helper connection to read available SMC sensors.")
                )
                .frame(height: 220)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        HStack(spacing: 12) {
                            Image(systemName: row.icon)
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).font(.headline)
                                Text(row.detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(row.value)
                                .font(.body.monospacedDigit())
                        }
                        .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 6)
            }
        } label: {
            Label("Sensor Readings", systemImage: "list.bullet.rectangle")
        }
    }
}
