import SwiftUI
import CurveFanCore

/// Native segmented mode picker + preset buttons. Replaces ControlModeChooser + ChoiceButton.
struct ModeAndPresetSection: View {
    let controlState: MenuControlState
    let presets: [Preset]
    let activePresetName: String?
    let isConnected: Bool
    let onSystemAuto: () -> Void
    let onSelectPreset: (Preset) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: pickerSelection) {
                Text("System Auto").tag(0)
                Text("CurveFan").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if controlState.isCurveFanControl || controlState == .externalManual {
                Divider()
                HStack(spacing: 7) {
                    ForEach(presets) { preset in
                        Button {
                            onSelectPreset(preset)
                        } label: {
                            Text(preset.name)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.bordered)
                        .tint(activePresetName == preset.name ? .accentColor : .secondary)
                        .disabled(!isConnected)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private var pickerSelection: Binding<Int> {
        Binding(
            get: { controlState.isCurveFanControl ? 1 : 0 },
            set: { if $0 == 0 { onSystemAuto() } }
        )
    }
}
