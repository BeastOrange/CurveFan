import SwiftUI
import Charts
import CurveFanCore

struct PageHeader: View {
    let subtitle: String
    let isConnected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(subtitle)
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            ConnectionStatusPill(isConnected: isConnected)
        }
    }
}

struct ConnectionStatusPill: View {
    let isConnected: Bool

    var body: some View {
        Label {
            Text(isConnected ? "Connected" : "Offline")
                .font(.callout.weight(.semibold))
        } icon: {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(isConnected ? .green : .red)
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(.regularMaterial, in: Capsule())
        .help(isConnected ? "Helper is connected" : "Helper is offline")
    }
}

/// Key-value metric rows using native Grid alignment.
struct NativeMetricTable: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.leading)
                    Text(row.1)
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .gridColumnAlignment(.leading)
                }
            }
        }
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
                    Text(preset.name).font(.headline)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark").font(.callout.weight(.semibold))
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
        } label: {
            Label("Preferences", systemImage: "gearshape")
        }
    }
}

/// RPM history chart using native Swift Charts.
struct RPMTrendChart: View {
    let samples: [RPMHistorySample]
    let currentRPM: Double?
    let minRPM: Double
    let maxRPM: Double

    var body: some View {
        Chart(chartData, id: \.index) { point in
            AreaMark(
                x: .value("Time", point.index),
                y: .value("RPM", point.rpm)
            )
            .opacity(0.12)
            LineMark(
                x: .value("Time", point.index),
                y: .value("RPM", point.rpm)
            )
            .interpolationMethod(.catmullRom)
            PointMark(
                x: .value("Time", point.index),
                y: .value("RPM", point.rpm)
            )
            .symbolSize(25)
        }
        .chartYScale(domain: minRPM...maxRPM)
        .chartXAxis(.hidden)
        .accessibilityLabel("RPM history")
    }

    private var chartData: [(index: Int, rpm: Double)] {
        let history = samples.map(\.rpm)
        let values: [Double] = history.count >= 2 ? history : Array(repeating: currentRPM ?? minRPM, count: 4)
        return values.enumerated().map { (index: $0.offset, rpm: $0.element) }
    }
}
