import SwiftUI

struct SettingsPageView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    subtitle: "FanFlow system behavior",
                    isConnected: isConnected
                )

                SettingsGeneralGroup(state: state)
                SettingsHelperGroup(state: state, isConnected: isConnected)
                SettingsAdvancedGroup(state: state)
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var isConnected: Bool {
        if case .connected = state.connectionStatus { return true }
        return false
    }
}

private struct SettingsGeneralGroup: View {
    @ObservedObject var state: AppState

    var body: some View {
        GroupBox {
            Form {
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
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 150)
        } label: {
            Label("General", systemImage: "gearshape")
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
        GroupBox {
            Form {
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
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 188)
        } label: {
            Label("Helper", systemImage: "bolt.horizontal")
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
        GroupBox {
            Form {
                LabeledContent("Control fallback") {
                    Text("Restore Auto on quit")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button("Quit FanFlow", role: .destructive) {
                        state.quitAfterRestoringAuto()
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 116)
        } label: {
            Label("Advanced", systemImage: "exclamationmark.triangle")
        }
    }
}
