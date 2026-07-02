import SwiftUI
import CurveFanCore

/// Compact header: native Gauge + RPM + status. No animations.
struct MenuHeaderCard: View {
    let rpm: Double?
    let minRPM: Double
    let maxRPM: Double
    let controlState: MenuControlState

    var body: some View {
        HStack(spacing: 14) {
            Gauge(value: rpm ?? minRPM, in: minRPM...maxRPM) {
                Image(systemName: "fan")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(controlState.tint)
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 5) {
                Label(controlState.title, systemImage: "circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(controlState.tint)
                    .labelStyle(TintedIconLabelStyle())

                Text(rpm.map { "\(formatRPM($0)) RPM" } ?? "-- RPM")
                    .font(.title2.bold().monospacedDigit())

                Text(controlState.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct TintedIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 8))
            configuration.title
        }
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
        VStack(spacing: 8) {
            HStack {
                Text("Manual target")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(formatRPM(clampedRPM)) RPM")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Slider(value: clampedBinding, in: safeRange, step: 100)
                    .disabled(!isConnected)
                Button(isActive ? "Update" : "Apply", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!isConnected)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.menuBarHeaderH)
        .padding(.vertical, DesignTokens.Spacing.menuBarHeaderV)
    }

    private var safeRange: ClosedRange<Double> {
        guard minRPM < maxRPM else { return 0...1 }
        return minRPM...maxRPM
    }

    private var clampedRPM: Double {
        guard minRPM < maxRPM else { return minRPM }
        return min(max(manualRPM, minRPM), maxRPM)
    }

    private var clampedBinding: Binding<Double> {
        Binding(
            get: { clampedRPM },
            set: { manualRPM = $0 }
        )
    }
}

struct FooterToolbar: View {
    let onOpenWindow: () -> Void
    let onSettings: () -> Void
    let onRestoreAuto: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpenWindow) {
                Label("Window", systemImage: "macwindow")
            }
            .buttonStyle(.borderless)

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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
