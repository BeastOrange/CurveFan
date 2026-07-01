import SwiftUI

struct SettingsPageView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                PageHeader(
                    subtitle: "CurveFan system behavior",
                    isConnected: isConnected
                )

                SettingsGeneralGroup(state: state)
                SettingsHelperGroup(state: state, isConnected: isConnected)
                SettingsAdvancedGroup(state: state)
            }
            .padding(DesignTokens.Spacing.page)
        }
    }

    private var isConnected: Bool { state.connectionStatus.isConnected }
}

private struct SettingsGeneralGroup: View {
    @ObservedObject var state: AppState

    var body: some View {
        FormCard(title: "General", systemImage: "gearshape") {
            Picker("Temperature unit", selection: $state.useFahrenheit) {
                Text("Celsius").tag(false)
                Text("Fahrenheit").tag(true)
            }
            .pickerStyle(.menu)

            Picker("Polling interval", selection: pollingBinding) {
                Text("1 second").tag(1.0)
                Text("2 seconds").tag(2.0)
                Text("5 seconds").tag(5.0)
            }
            .pickerStyle(.menu)

            Toggle("Show RPM in menu bar", isOn: $state.showMenuBarRPM)
        }
    }

    private var pollingBinding: Binding<TimeInterval> {
        Binding(
            get: { state.pollingInterval },
            set: { state.setPollingInterval($0) }
        )
    }
}

private struct SettingsHelperGroup: View {
    @ObservedObject var state: AppState
    let isConnected: Bool

    var body: some View {
        FormCard(title: "Helper", systemImage: "bolt.horizontal") {
            LabeledContent("Helper IPC") {
                Label(connectionText, systemImage: "circle.fill")
                    .foregroundStyle(isConnected ? .green : .red)
            }

            LabeledContent("Last refresh") {
                Text(state.lastPollDate?.formatted(date: .omitted, time: .standard) ?? "--")
                    .monospacedDigit()
            }

            LabeledContent("Primary sensor") {
                Text(state.defaultSensorKey.isEmpty ? "Pending" : state.defaultSensorKey)
            }

            HStack {
                Spacer()
                Button("Refresh Helper") {
                    Task { await state.checkDaemon() }
                }
                Button("Restore System Auto") {
                    Task { await state.restoreAuto() }
                }
            }
        }
    }

    private var connectionText: String {
        switch state.connectionStatus {
        case .connected: return "Connected"
        case .disconnected: return "Offline"
        case .error: return "Error"
        }
    }
}

private struct SettingsAdvancedGroup: View {
    @ObservedObject var state: AppState

    var body: some View {
        FormCard(title: "Advanced", systemImage: "exclamationmark.triangle") {
            LabeledContent("Control fallback") {
                Text("Restore Auto on quit")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Quit CurveFan", role: .destructive) {
                    state.quitAfterRestoringAuto()
                }
            }
        }
    }
}
