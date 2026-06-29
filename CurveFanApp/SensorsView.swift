import SwiftUI
import CurveFanCore

struct SensorsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SensorSummaryItem(title: "Hottest", value: hottestText, icon: "thermometer.high")
                SensorSummaryItem(title: "Average", value: averageText, icon: "gauge.with.dots.needle.50percent")
                SensorSummaryItem(title: "Unit", value: state.useFahrenheit ? "Fahrenheit" : "Celsius", icon: "ruler")
            }
            .padding(16)
            Divider()
            if rows.isEmpty {
                ContentUnavailableView(
                    "No sensor readings",
                    systemImage: "thermometer",
                    description: Text("Refresh helper connection to read available SMC sensors.")
                )
            } else {
                List(rows) { row in
                    HStack(spacing: 12) {
                        Image(systemName: row.icon)
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name).font(.body)
                            Text(row.detail).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(row.value).font(.body.monospacedDigit())
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
        }
    }

    private var rows: [SensorDisplayRow] {
        let thermal = state.temperatures.sorted {
            $0.group == $1.group ? $0.name < $1.name : groupRank($0.group) < groupRank($1.group)
        }.map {
            SensorDisplayRow(name: $0.name, detail: "\($0.key) — \($0.group.rawValue)",
                             value: state.formatTemp($0.value), icon: icon(for: $0.group))
        }
        let fans = state.fanInfo.keys.sorted().compactMap { fan -> SensorDisplayRow? in
            guard let info = state.fanInfo[fan] else { return nil }
            return SensorDisplayRow(
                name: fan == 0 ? "System Fan Tach" : "Fan \(fan + 1) Tach",
                detail: "F\(fan)Ac — fan",
                value: "\(formatRPM(info.actualRPM)) RPM",
                icon: "fan"
            )
        }
        return thermal + fans
    }

    private var hottestText: String {
        guard let v = state.temperatures.map(\.value).max() else { return "--" }
        return state.formatTemp(v)
    }

    private var averageText: String {
        guard !state.temperatures.isEmpty else { return "--" }
        return state.formatTemp(state.temperatures.reduce(0) { $0 + $1.value } / Double(state.temperatures.count))
    }

    private func groupRank(_ g: SensorGroup) -> Int {
        switch g {
        case .cpu: return 0; case .gpu: return 1; case .memory: return 2
        case .system: return 3; case .fan: return 4
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

private struct SensorSummaryItem: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 76)
        }
    }
}
