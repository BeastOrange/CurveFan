import SwiftUI
import CurveFanCore

struct PageHeader: View {
    let subtitle: String
    let isConnected: Bool
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(subtitle)
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            ConnectionStatusPill(isConnected: isConnected, onRetry: onRetry)
        }
    }
}

struct ConnectionStatusPill: View {
    let isConnected: Bool
    var onRetry: (() -> Void)? = nil

    var body: some View {
        let label = Label {
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
        .help(isConnected ? "Helper is connected" : "Tap to retry connecting to helper")

        if !isConnected, let onRetry {
            label.onTapGesture { onRetry() }
        } else {
            label
        }
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
        FormCard(title: "Preferences", systemImage: "gearshape") {
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
    }
}

/// RPM history chart rendered on a continuous time axis for smoother streaming updates.
struct RPMTrendChart: View {
    let samples: [RPMHistorySample]
    let currentRPM: Double?
    let minRPM: Double
    let maxRPM: Double
    let pollingInterval: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var latestTransition: LatestSampleTransition?

    var body: some View {
        TimelineView(.periodic(from: .now, by: frameInterval)) { context in
            Canvas(opaque: false, rendersAsynchronously: true) { canvasContext, size in
                drawChart(context: canvasContext, size: size, now: context.date)
            }
            .accessibilityLabel("RPM history")
        }
        .onAppear {
            syncLatestTransition(initial: true)
        }
        .onChange(of: samples) { _, _ in
            syncLatestTransition(initial: false)
        }
        .onChange(of: reduceMotion) { _, _ in
            syncLatestTransition(initial: true)
        }
        .onChange(of: currentRPM) { _, _ in
            if samples.isEmpty {
                latestTransition = nil
            }
        }
    }

    private var frameInterval: TimeInterval {
        reduceMotion ? max(pollingInterval, 1.0) : 1.0 / 30.0
    }

    private var animationDuration: TimeInterval {
        min(0.35, pollingInterval * 0.25)
    }

    private var timeWindow: TimeInterval {
        max(pollingInterval * 48, pollingInterval)
    }

    private func drawChart(context: GraphicsContext, size: CGSize, now: Date) {
        let rect = plotRect(size: size)
        guard rect.width > 1, rect.height > 1 else { return }

        drawGrid(context: context, rect: rect)

        let latestValue = latestVisualRPM(now: now)
        let plottedPoints = plottedPoints(in: rect, now: now, latestValue: latestValue)
        guard let latestPoint = plottedPoints.last, plottedPoints.count >= 2 else {
            drawEmptyLine(context: context, rect: rect, rpm: latestValue)
            return
        }

        let linePath = monotonePath(points: plottedPoints)
        var areaPath = linePath
        areaPath.addLine(to: CGPoint(x: latestPoint.x, y: rect.maxY))
        areaPath.addLine(to: CGPoint(x: plottedPoints[0].x, y: rect.maxY))
        areaPath.closeSubpath()

        context.fill(areaPath, with: .color(.accentColor.opacity(0.14)))
        context.stroke(
            linePath,
            with: .color(.accentColor),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        )

        let haloRect = CGRect(x: latestPoint.x - 6, y: latestPoint.y - 6, width: 12, height: 12)
        context.fill(Path(ellipseIn: haloRect), with: .color(.accentColor.opacity(0.18)))

        let dotRect = CGRect(x: latestPoint.x - 3.5, y: latestPoint.y - 3.5, width: 7, height: 7)
        let dot = Path(ellipseIn: dotRect)
        context.fill(dot, with: .color(.accentColor))
        context.stroke(dot, with: .color(.white.opacity(0.9)), lineWidth: 1)
    }

    private func latestVisualRPM(now: Date) -> Double {
        guard let latestSample = samples.last else { return currentRPM ?? minRPM }
        return latestTransition?.displayedRPM(
            for: latestSample,
            at: now,
            duration: animationDuration,
            reduceMotion: reduceMotion
        ) ?? latestSample.rpm
    }

    private func syncLatestTransition(initial: Bool) {
        guard let latest = samples.last else {
            latestTransition = nil
            return
        }

        if initial || reduceMotion {
            latestTransition = LatestSampleTransition(
                sampleID: latest.id,
                fromRPM: latest.rpm,
                toRPM: latest.rpm,
                startedAt: latest.date
            )
            return
        }

        if latestTransition?.sampleID == latest.id {
            return
        }

        let previousRPM = latestTransition?.toRPM ?? samples.dropLast().last?.rpm ?? latest.rpm
        latestTransition = LatestSampleTransition(
            sampleID: latest.id,
            fromRPM: previousRPM,
            toRPM: latest.rpm,
            startedAt: latest.date
        )
    }

    private func plottedPoints(in rect: CGRect, now: Date, latestValue: Double) -> [CGPoint] {
        let lowerBound = now.addingTimeInterval(-timeWindow)
        return displaySamples(now: now, latestValue: latestValue)
            .filter { $0.date >= lowerBound }
            .map { sample in
                CGPoint(
                    x: xPosition(for: sample.date, now: now, lowerBound: lowerBound, rect: rect),
                    y: yPosition(for: sample.rpm, rect: rect)
                )
            }
    }

    private func displaySamples(now: Date, latestValue: Double) -> [DisplayRPMPoint] {
        if samples.count >= 2 {
            var values = samples.enumerated().map { index, sample in
                let rpm = index == samples.index(before: samples.endIndex) ? latestValue : sample.rpm
                return DisplayRPMPoint(date: sample.date, rpm: rpm)
            }
            if let latestDate = values.last?.date, latestDate < now {
                values.append(DisplayRPMPoint(date: now, rpm: latestValue))
            }
            return values
        }

        let baseRPM = samples.last?.rpm ?? currentRPM ?? minRPM
        let end = max(samples.last?.date ?? now, now)
        let start = end.addingTimeInterval(-max(pollingInterval, 1.0))
        return [
            DisplayRPMPoint(date: start, rpm: baseRPM),
            DisplayRPMPoint(date: end, rpm: latestValue)
        ]
    }

    private func drawGrid(context: GraphicsContext, rect: CGRect) {
        var grid = Path()
        for rpm in gridRPMValues {
            let y = yPosition(for: rpm, rect: rect)
            grid.move(to: CGPoint(x: rect.minX, y: y))
            grid.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        context.stroke(grid, with: .color(.secondary.opacity(0.12)), lineWidth: 1)

        let border = Path(roundedRect: rect, cornerRadius: 10)
        context.stroke(border, with: .color(.secondary.opacity(0.18)), lineWidth: 1)

        for rpm in [maxRPM, minRPM] {
            let label = context.resolve(Text(formatRPM(rpm)).font(.caption2).foregroundStyle(.secondary))
            let y = min(max(yPosition(for: rpm, rect: rect), rect.minY + 10), rect.maxY - 10)
            context.draw(label, at: CGPoint(x: rect.minX + 6, y: y), anchor: .leading)
        }
    }

    private func drawEmptyLine(context: GraphicsContext, rect: CGRect, rpm: Double) {
        let y = yPosition(for: rpm, rect: rect)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        context.stroke(
            path,
            with: .color(.accentColor.opacity(0.55)),
            style: StrokeStyle(lineWidth: 2, lineCap: .round)
        )
    }

    private var gridRPMValues: [Double] {
        [minRPM, minRPM + (maxRPM - minRPM) / 2, maxRPM]
    }

    private func plotRect(size: CGSize) -> CGRect {
        CGRect(x: 0, y: 8, width: max(size.width, 1), height: max(size.height - 16, 1))
    }

    private func xPosition(for date: Date, now: Date, lowerBound: Date, rect: CGRect) -> CGFloat {
        let total = max(now.timeIntervalSince(lowerBound), 0.001)
        let elapsed = min(max(date.timeIntervalSince(lowerBound), 0), total)
        return rect.minX + CGFloat(elapsed / total) * rect.width
    }

    private func yPosition(for rpm: Double, rect: CGRect) -> CGFloat {
        let clamped = min(max(rpm, minRPM), maxRPM)
        let span = max(maxRPM - minRPM, 1)
        let ratio = (clamped - minRPM) / span
        return rect.maxY - CGFloat(ratio) * rect.height
    }

    private func monotonePath(points: [CGPoint]) -> Path {
        guard points.count > 1 else {
            var path = Path()
            if let first = points.first {
                path.move(to: first)
            }
            return path
        }

        let x = points.map { Double($0.x) }
        let y = points.map { Double($0.y) }
        let tangents = monotoneTangents(x: x, y: y)

        var path = Path()
        path.move(to: points[0])
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let dx = CGFloat(x[index + 1] - x[index])
            guard dx > 0 else {
                path.addLine(to: end)
                continue
            }

            let control1 = CGPoint(
                x: start.x + dx / 3,
                y: start.y + CGFloat(tangents[index]) * dx / 3
            )
            let control2 = CGPoint(
                x: end.x - dx / 3,
                y: end.y - CGFloat(tangents[index + 1]) * dx / 3
            )
            path.addCurve(to: end, control1: control1, control2: control2)
        }
        return path
    }

    private func monotoneTangents(x: [Double], y: [Double]) -> [Double] {
        let count = x.count
        guard count > 1 else { return Array(repeating: 0, count: count) }

        var slopes = Array(repeating: 0.0, count: count - 1)
        for index in 0..<(count - 1) {
            let dx = x[index + 1] - x[index]
            slopes[index] = dx == 0 ? 0 : (y[index + 1] - y[index]) / dx
        }

        var tangents = Array(repeating: 0.0, count: count)
        tangents[0] = slopes[0]
        tangents[count - 1] = slopes[count - 2]

        if count > 2 {
            for index in 1..<(count - 1) {
                let previous = slopes[index - 1]
                let next = slopes[index]
                if previous == 0 || next == 0 || previous.sign != next.sign {
                    tangents[index] = 0
                } else {
                    tangents[index] = (previous + next) / 2
                }
            }
        }

        for index in 0..<(count - 1) {
            let slope = slopes[index]
            if slope == 0 {
                tangents[index] = 0
                tangents[index + 1] = 0
                continue
            }

            let a = tangents[index] / slope
            let b = tangents[index + 1] / slope
            let magnitude = hypot(a, b)
            if magnitude > 3 {
                let scale = 3 / magnitude
                tangents[index] = scale * a * slope
                tangents[index + 1] = scale * b * slope
            }
        }

        return tangents
    }
}

private struct LatestSampleTransition {
    let sampleID: UUID
    let fromRPM: Double
    let toRPM: Double
    let startedAt: Date

    func displayedRPM(
        for sample: RPMHistorySample,
        at now: Date,
        duration: TimeInterval,
        reduceMotion: Bool
    ) -> Double {
        guard sample.id == sampleID else { return sample.rpm }
        guard !reduceMotion else { return toRPM }

        let progress = min(max(now.timeIntervalSince(startedAt) / max(duration, 0.001), 0), 1)
        let eased = 1 - pow(1 - progress, 3)
        return fromRPM + (toRPM - fromRPM) * eased
    }
}

private struct DisplayRPMPoint {
    let date: Date
    let rpm: Double
}
