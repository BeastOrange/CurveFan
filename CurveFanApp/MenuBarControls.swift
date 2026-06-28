import SwiftUI
import CurveFanCore

struct ControlModeChooser: View {
    let controlState: MenuControlState
    let curveName: String
    let onSystemAuto: () -> Void
    let onFanFlow: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ChoiceButton(
                title: "System Auto",
                subtitle: "macOS controls",
                icon: "checkmark.shield",
                isSelected: controlState == .system,
                tint: .green,
                action: onSystemAuto
            )
            ChoiceButton(
                title: "FanFlow Control",
                subtitle: "\(curveName) curve",
                icon: "waveform.path.ecg",
                isSelected: controlState.isFanFlowControl,
                tint: .blue,
                action: onFanFlow
            )
        }
    }
}

struct ChoiceButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isSelected ? tint : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 62)
        }
        .buttonStyle(.plain)
        .background(choiceBackground)
        .overlay(cardStroke(radius: 8, tint: isSelected ? tint.opacity(0.55) : Color.white.opacity(0.08)))
    }

    private var choiceBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? tint.opacity(0.16) : Color.primary.opacity(0.055))
    }
}

struct PresetStrip: View {
    let presets: [Preset]
    let activePresetName: String?
    let isEnabled: Bool
    let onSelect: (Preset) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(presets) { preset in
                Button {
                    onSelect(preset)
                } label: {
                    Text(preset.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .foregroundStyle(activePresetName == preset.name ? .white : .primary)
                .background(presetBackground(isActive: activePresetName == preset.name))
            }
        }
    }

    private func presetBackground(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isActive ? Color.accentColor : Color.primary.opacity(0.065))
    }
}

struct ManualTargetCard: View {
    @Binding var manualRPM: Double
    let minRPM: Double
    let maxRPM: Double
    let isConnected: Bool
    let isActive: Bool
    let onApply: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Manual target")
                        .font(.system(size: 13, weight: .semibold))
                    Text(isActive ? "Fixed RPM is active" : "Applies FanFlow manual override")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(formatRPM(manualRPM)) RPM")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                Slider(value: $manualRPM, in: minRPM...maxRPM, step: 100)
                    .disabled(!isConnected)
                Button(isActive ? "Update" : "Apply") {
                    onApply()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isConnected)
                .controlSize(.small)
            }
        }
        .padding(11)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct FooterToolbar: View {
    let onSettings: () -> Void
    let onRestoreAuto: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSettings) {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button(action: onRestoreAuto) {
                Label("Restore Auto", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)

            Button(role: .destructive, action: onQuit) {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.borderless)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 2)
    }
}
