import SwiftUI
import Charts
import CurveFanCore

struct PresetsView: View {
    @ObservedObject var state: AppState
    @State private var selectedPresetID: PresetSelection = .builtIn("Balanced")
    @State private var editorMode: PresetEditorMode?
    @State private var pendingDelete: Preset?
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                PageHeader(
                    subtitle: "Native macOS preset management",
                    isConnected: isConnected,
                    onRetry: { Task { await state.reconnect() } }
                )

                HStack(alignment: .top, spacing: DesignTokens.Spacing.section) {
                    PresetLibraryGroup(
                        builtInPresets: state.builtInPresets,
                        customPresets: state.customPresets,
                        selectedPresetID: $selectedPresetID,
                        activePreset: state.activePreset,
                        onCreate: { editorMode = .create }
                    )
                    .frame(minWidth: 300, maxWidth: 420)

                    PresetDetailGroup(
                        preset: selectedPreset,
                        state: state,
                        isConnected: isConnected,
                        isCustom: selectedPresetID.customID != nil,
                        onEdit: { editorMode = .edit(selectedPreset) },
                        onDelete: { confirmDelete(selectedPreset) }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(DesignTokens.Spacing.page)
        }
        .sheet(item: $editorMode) { mode in
            PresetEditorView(state: state, preset: mode.preset) { savedPreset in
                selectedPresetID = .custom(savedPreset.id)
            }
        }
        .confirmationDialog(
            "Delete preset?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deletePendingPreset() }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        .alert("Preset Error", isPresented: errorBinding) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: state.customPresets) { _, _ in normalizeSelection() }
    }

    private var selectedPreset: Preset {
        switch selectedPresetID {
        case .builtIn(let name):
            return state.builtInPresets.first { $0.name == name } ??
                state.builtInPresets.first { $0.name == "Balanced" } ??
                .auto
        case .custom(let id):
            return state.customPresets.first { $0.id == id } ??
                state.builtInPresets.first { $0.name == "Balanced" } ??
                .auto
        }
    }

    private var isConnected: Bool { state.connectionStatus.isConnected }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func confirmDelete(_ preset: Preset) {
        pendingDelete = preset
        showingDeleteConfirmation = true
    }

    private func deletePendingPreset() {
        guard let preset = pendingDelete else { return }
        pendingDelete = nil
        Task {
            do {
                try await PresetViewModel.shared.delete(id: preset.id)
                if selectedPresetID == .custom(preset.id) {
                    selectedPresetID = .builtIn("Balanced")
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func normalizeSelection() {
        if case .custom(let id) = selectedPresetID,
           !state.customPresets.contains(where: { $0.id == id }) {
            selectedPresetID = .builtIn("Balanced")
        }
    }
}

private enum PresetSelection: Hashable {
    case builtIn(String)
    case custom(UUID)

    var customID: UUID? {
        if case .custom(let id) = self { return id }
        return nil
    }
}

private enum PresetEditorMode: Identifiable {
    case create
    case edit(Preset)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let preset): return preset.id.uuidString
        }
    }

    var preset: Preset? {
        if case .edit(let preset) = self { return preset }
        return nil
    }
}

private struct PresetLibraryGroup: View {
    let builtInPresets: [Preset]
    let customPresets: [Preset]
    @Binding var selectedPresetID: PresetSelection
    let activePreset: Preset?
    let onCreate: () -> Void

    var body: some View {
        GroupBox {
            VStack(spacing: 10) {
                HStack {
                    Button {
                        onCreate()
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    Spacer()
                }

                List(selection: $selectedPresetID) {
                    Section("Built-in") {
                        ForEach(builtInPresets, id: \.name) { preset in
                            PresetLibraryRow(
                                preset: preset,
                                isActive: isActive(preset, selection: .builtIn(preset.name))
                            )
                            .tag(PresetSelection.builtIn(preset.name))
                        }
                    }

                    Section("Custom") {
                        if customPresets.isEmpty {
                            Text("No custom presets")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(customPresets) { preset in
                                PresetLibraryRow(
                                    preset: preset,
                                    isActive: isActive(preset, selection: .custom(preset.id))
                                )
                                .tag(PresetSelection.custom(preset.id))
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 470)
            }
        } label: {
            Label("Preset Library", systemImage: "slider.horizontal.3")
        }
    }

    private func isActive(_ preset: Preset, selection: PresetSelection) -> Bool {
        switch selection {
        case .builtIn:
            return activePreset?.name == preset.name ||
                (activePreset == nil && preset.isAuto)
        case .custom:
            return activePreset?.id == preset.id
        }
    }
}

private struct PresetLibraryRow: View {
    let preset: Preset
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(String(preset.name.prefix(1)))
                .font(.headline)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(isActive ? 0.85 : 0.16), in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(isActive ? .white : .primary)

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name).font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(rangeText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 8)
    }

    private var description: String {
        switch preset.name {
        case "Auto": return "System controlled curve"
        case "Quiet": return "Lower fan noise for light work"
        case "Balanced": return "Recommended daily profile"
        case "MaxCool": return "Maximum thermal headroom"
        default: return "Custom fan curve"
        }
    }

    private var rangeText: String {
        guard let curve = preset.fanToCurve[0], !curve.points.isEmpty else {
            return "System Auto"
        }
        let rpms = curve.points.map(\.rpm).filter { $0 > 0 }
        guard let min = rpms.min(), let max = rpms.max() else { return "System Auto" }
        return "\(formatRPM(Double(min)))-\(formatRPM(Double(max))) RPM"
    }
}

private struct PresetDetailGroup: View {
    let preset: Preset
    @ObservedObject var state: AppState
    let isConnected: Bool
    let isCustom: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        CardView(title: "Preset Details", systemImage: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                header

                NativeMetricTable(rows: [
                    ("Mode", preset.isAuto ? "System" : "Curve"),
                    ("Fans", "\(state.knownFanCount)"),
                    ("Range", rangeText)
                ])

                CurvePreviewGroup(curve: preset.fanToCurve[0], minRPM: state.minRPM, maxRPM: state.maxRPM)

                NativeMetricTable(rows: [
                    ("Temperature units", state.useFahrenheit ? "Fahrenheit" : "Celsius"),
                    ("Polling interval", "\(Int(state.pollingInterval)) seconds"),
                    ("Fallback mode", "System Auto")
                ])

                actionButtons
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(preset.name)
                    .font(.largeTitle.weight(.semibold))
                Text(detail)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCustom {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            Spacer()
            Button("Restore Auto") {
                Task { await state.restoreAuto() }
            }
            Button(applyTitle) {
                Task { await state.applyPreset(preset) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canApply)
        }
    }

    private var detail: String {
        switch preset.name {
        case "Auto": return "macOS owns the fan controller."
        case "Quiet": return "A light curve for low-noise work."
        case "Balanced": return "Stable thermals without ramping early."
        case "MaxCool": return "Aggressive cooling for sustained load."
        default: return "Custom temperature response."
        }
    }

    private var rangeText: String {
        guard let curve = preset.fanToCurve[0], !curve.points.isEmpty else { return "System" }
        let rpms = curve.points.map(\.rpm).filter { $0 > 0 }
        guard let min = rpms.min(), let max = rpms.max() else { return "System" }
        return "\(formatRPM(Double(min)))-\(formatRPM(Double(max)))"
    }

    private var applyTitle: String {
        preset.isAuto ? "Apply Auto" : "Apply \(preset.name)"
    }

    private var canApply: Bool {
        isConnected && (preset.isAuto || hasSensor)
    }

    private var hasSensor: Bool {
        guard let curve = preset.fanToCurve[0] else { return false }
        return !(preset.fanToSensor[0] ?? curve.sensorKey).isEmpty
    }
}

private struct PresetEditorView: View {
    private static let startTemperatureOptions = stride(from: 0, through: 25, by: 5).map(Double.init)

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: AppState
    let preset: Preset?
    let onSave: (Preset) -> Void

    @State private var name: String
    @State private var sensorKey: String
    @State private var startTemperature: Double
    @State private var points: [CurvePoint]
    @State private var errorMessage: String?

    init(state: AppState, preset: Preset?, onSave: @escaping (Preset) -> Void) {
        self.state = state
        self.preset = preset
        self.onSave = onSave
        _name = State(initialValue: preset?.name ?? "")
        _sensorKey = State(initialValue: preset?.fanToSensor[0] ?? preset?.fanToCurve[0]?.sensorKey ?? state.defaultSensorKey)
        let initialStart = preset?.fanToCurve[0]?.points.first?.temperature ?? 20
        _startTemperature = State(initialValue: Self.clampedStartTemperature(initialStart))
        _points = State(initialValue: preset?.fanToCurve[0]?.points ?? [
            CurvePoint(temperature: 20, rpm: Int(state.minRPM)),
            CurvePoint(temperature: 100, rpm: Int(state.maxRPM))
        ])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
            HStack {
                Text(preset == nil ? "New Preset" : "Edit Preset")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { savePreset() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }

            Form {
                TextField("Name", text: $name)
                sensorPicker
                startTemperaturePicker
            }
            .formStyle(.grouped)

            CurveEditorView(
                points: $points,
                minRPM: state.minRPM,
                maxRPM: state.maxRPM,
                startTemperature: startTemperature
            )
                .frame(minHeight: 330)

            if let errorMessage {
                AlertBanner(icon: "exclamationmark.triangle", text: errorMessage, tint: .orange)
            }
        }
        .padding(22)
        .frame(width: 720)
        .frame(minHeight: 600)
        .onAppear {
            selectDefaultSensorIfNeeded()
            normalizePointsForStartTemperature()
        }
        .onChange(of: state.defaultSensorKey) { _, _ in selectDefaultSensorIfNeeded() }
        .onChange(of: startTemperature) { _, _ in
            normalizePointsForStartTemperature()
        }
    }

    private var sensorPicker: some View {
        Picker("Sensor", selection: $sensorKey) {
            if state.temperatures.isEmpty {
                Text("No readable temperature sensors").tag("")
            } else {
                ForEach(state.temperatures, id: \.key) { sensor in
                    Text("\(sensor.name) (\(sensor.key))").tag(sensor.key)
                }
            }
        }
    }

    private var startTemperaturePicker: some View {
        LabeledContent("Start temp") {
            Slider(
                value: $startTemperature,
                in: (Self.startTemperatureOptions.first ?? 0)...(Self.startTemperatureOptions.last ?? 25),
                step: 5,
                label: { Text("Start temp") },
                tick: { value in
                    SliderTick(value) {
                        Text("\(Int(value))°C")
                            .font(.caption2)
                    }
                }
            )
            .labelsHidden()
            .frame(minWidth: 280)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rpmRange: ClosedRange<Int> {
        Int(min(state.minRPM, state.maxRPM))...Int(max(state.minRPM, state.maxRPM))
    }

    private var validationErrors: [String] {
        if trimmedName.isEmpty { return ["Preset name is required"] }
        if sensorKey.isEmpty { return ["No readable temperature sensor for preset"] }
        let curve = FanCurve(name: trimmedName, points: sortedPoints, sensorKey: sensorKey)
        return curve.validate(rpmRange: rpmRange)
    }

    private var sortedPoints: [CurvePoint] {
        points.sorted { $0.temperature < $1.temperature }
    }

    private var canSave: Bool {
        validationErrors.isEmpty
    }

    private func selectDefaultSensorIfNeeded() {
        guard sensorKey.isEmpty, !state.defaultSensorKey.isEmpty else { return }
        sensorKey = state.defaultSensorKey
    }

    private func normalizePointsForStartTemperature() {
        let normalizedStart = Self.clampedStartTemperature(startTemperature)
        if startTemperature != normalizedStart {
            startTemperature = normalizedStart
            return
        }

        var updated = sortedPoints
        if updated.isEmpty {
            updated = [
                CurvePoint(temperature: normalizedStart, rpm: Int(state.minRPM)),
                CurvePoint(temperature: 100, rpm: Int(state.maxRPM))
            ]
        }

        let firstRPM = updated.first?.rpm ?? Int(state.minRPM)
        updated[0] = CurvePoint(temperature: normalizedStart, rpm: firstRPM)
        updated = updated.filter { point in
            (point.temperature == normalizedStart || point.temperature >= normalizedStart + 1)
                && point.temperature <= 100
        }

        if updated.count < 2 {
            updated.append(CurvePoint(temperature: 100, rpm: Int(state.maxRPM)))
        }

        // The last point must sit exactly at 100°C. Older presets could store points
        // beyond 100° (the temperature ceiling used to be 120°); drop/clamp them here.
        if updated.last!.temperature < 100 {
            updated.append(CurvePoint(temperature: 100, rpm: max(updated.last!.rpm, Int(state.minRPM))))
        } else if updated.last!.temperature > 100 {
            updated[updated.count - 1] = CurvePoint(temperature: 100, rpm: max(updated.last!.rpm, Int(state.minRPM)))
        }

        points = updated.sorted { $0.temperature < $1.temperature }
    }

    private static func clampedStartTemperature(_ value: Double) -> Double {
        if let exact = startTemperatureOptions.first(where: { abs($0 - value) < 0.5 }) {
            return exact
        }
        return startTemperatureOptions.min(by: { abs($0 - value) < abs($1 - value) }) ?? 20
    }

    private func savePreset() {
        let errors = validationErrors
        guard errors.isEmpty else {
            errorMessage = errors.joined(separator: "\n")
            return
        }
        let saved = makePreset()
        Task {
            do {
                try await PresetViewModel.shared.save(saved)
                onSave(saved)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func makePreset() -> Preset {
        let fanIDs = Array(0..<state.knownFanCount)
        let curveID = preset?.fanToCurve[0]?.id ?? UUID()
        let curve = FanCurve(id: curveID, name: trimmedName, points: sortedPoints, sensorKey: sensorKey)
        let fanToCurve = Dictionary(uniqueKeysWithValues: fanIDs.map { ($0, curve) })
        let fanToSensor = Dictionary(uniqueKeysWithValues: fanIDs.map { ($0, sensorKey) })
        return Preset(
            id: preset?.id ?? UUID(),
            name: trimmedName,
            fanToCurve: fanToCurve,
            fanToSensor: fanToSensor,
            createdAt: preset?.createdAt ?? Date()
        )
    }
}

private struct CurvePreviewGroup: View {
    let curve: FanCurve?
    let minRPM: Double
    let maxRPM: Double

    var body: some View {
        CardView(title: "Fan Curve Preview", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
            if let curve, !curve.points.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Temperature response - Celsius")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    CurvePreview(curve: curve, minRPM: minRPM, maxRPM: maxRPM)
                        .frame(height: 170)
                }
            } else {
                Text("System Auto has no CurveFan curve preview.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CurvePreview: View {
    let curve: FanCurve
    let minRPM: Double
    let maxRPM: Double

    var body: some View {
        Chart {
            ForEach(sampledPoints, id: \.temperature) { point in
                AreaMark(
                    x: .value("Temp", point.temperature),
                    yStart: .value("Min RPM", chartMinRPM),
                    yEnd: .value("RPM", displayRPM(point.rpm))
                )
                    .opacity(0.12)
                LineMark(x: .value("Temp", point.temperature), y: .value("RPM", displayRPM(point.rpm)))
            }
            ForEach(curve.points, id: \.temperature) { point in
                PointMark(x: .value("Temp", point.temperature), y: .value("RPM", displayRPM(point.rpm)))
                    .symbolSize(30)
            }
        }
        .chartXScale(domain: (curve.points.first?.temperature ?? 0)...100)
        .chartYScale(domain: chartMinRPM...maxRPM)
        .chartXAxisLabel("°C")
        .accessibilityLabel("Fan curve preview")
    }

    private var chartMinRPM: Double {
        minRPM
    }

    private func displayRPM(_ rpm: Int) -> Double {
        if rpm == 0 { return chartMinRPM }
        return min(max(Double(rpm), chartMinRPM), maxRPM)
    }

    private var sampledPoints: [CurvePoint] {
        guard let first = curve.points.first, let last = curve.points.last else { return [] }
        let lower = Int(first.temperature.rounded(.down))
        let upper = 100  // Always sample through 100°C for consistent chart bounds
        let samples = stride(from: lower, through: upper, by: 1).map { value in
            let temp = Double(value)
            return CurvePoint(
                temperature: temp,
                rpm: curve.rpm(for: temp, minRPM: Int(minRPM), maxRPM: Int(maxRPM))
            )
        }
        return uniqueCurvePoints(samples + [first, last])
            .map { point in
                CurvePoint(temperature: point.temperature, rpm: Int(displayRPM(point.rpm).rounded()))
            }
    }
}

private func uniqueCurvePoints(_ points: [CurvePoint]) -> [CurvePoint] {
    var unique: [Double: CurvePoint] = [:]
    for point in points {
        unique[point.temperature] = point
    }
    return unique.values.sorted { $0.temperature < $1.temperature }
}
