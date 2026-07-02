import SwiftUI
import Charts
import CurveFanCore

struct CurveEditorView: View {
    @Binding var points: [CurvePoint]
    let minRPM: Double
    let maxRPM: Double
    let startTemperature: Double

    @State private var selectedIndex: Int?
    @State private var dragIndex: Int?

    private var tempRange: ClosedRange<Double> {
        startTemperature...100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                Canvas { context, size in
                    drawEditor(context: context, size: size)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(size: geometry.size))
            }
            .frame(minHeight: 260)

            HStack {
                Button {
                    addPoint()
                } label: {
                    Label("Add Point", systemImage: "plus")
                }
                Button(role: .destructive) {
                    deleteSelectedPoint()
                } label: {
                    Label("Delete Point", systemImage: "trash")
                }
                .disabled(selectedIndex == nil || points.count <= 2)
                Spacer()
                Text("\(Int(tempRange.lowerBound))-\(Int(tempRange.upperBound))°C · \(formatRPM(minRPM))-\(formatRPM(maxRPM)) RPM")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragIndex == nil {
                    dragIndex = nearestPoint(to: value.startLocation, size: size)
                }
                guard let index = dragIndex else { return }
                selectedIndex = index
                updatePoint(at: index, location: value.location, size: size)
            }
            .onEnded { value in
                if dragIndex == nil {
                    addPoint(at: value.location, size: size)
                }
                dragIndex = nil
            }
    }

    private func drawEditor(context: GraphicsContext, size: CGSize) {
        let border = plotRect(size: size)
        let content = pointRect(size: size)
        drawGrid(context: context, border: border, content: content)
        drawCurve(context: context, rect: content)
        drawPoints(context: context, rect: content)
    }

    private func drawGrid(context: GraphicsContext, border: CGRect, content: CGRect) {
        let temps = gridTemperatures
        let rpms = stride(from: Int(minRPM), through: Int(maxRPM), by: max(Int((maxRPM - minRPM) / 4), 1)).map(Double.init)
        var grid = Path()

        for temp in temps {
            let x = xPosition(for: temp, rect: content)
            grid.move(to: CGPoint(x: x, y: border.minY))
            grid.addLine(to: CGPoint(x: x, y: border.maxY))
        }
        for rpm in rpms {
            let y = yPosition(for: rpm, rect: content)
            grid.move(to: CGPoint(x: border.minX, y: y))
            grid.addLine(to: CGPoint(x: border.maxX, y: y))
        }

        context.stroke(grid, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
        context.stroke(Path(border), with: .color(.secondary.opacity(0.35)), lineWidth: 1)

        for temp in temps {
            let text = context.resolve(Text("\(Int(temp))°").font(.caption2).foregroundStyle(.secondary))
            context.draw(text, at: CGPoint(x: xPosition(for: temp, rect: content), y: border.maxY + 14), anchor: .center)
        }
        for rpm in [minRPM, maxRPM] {
            let text = context.resolve(Text(formatRPM(rpm)).font(.caption2).foregroundStyle(.secondary))
            context.draw(text, at: CGPoint(x: border.minX - 8, y: yPosition(for: rpm, rect: content)), anchor: .trailing)
        }
    }

    private func drawCurve(context: GraphicsContext, rect: CGRect) {
        let sorted = sortedPoints
        guard let first = sorted.first else { return }
        let curve = FanCurve(points: sorted)
        let samples = sampledCurvePoints(for: curve)
        var path = Path()
        path.move(to: pointPosition(first, rect: rect))
        for point in samples.dropFirst() {
            path.addLine(to: pointPosition(point, rect: rect))
        }
        context.stroke(path, with: .color(.accentColor), lineWidth: 2.5)
    }

    private func drawPoints(context: GraphicsContext, rect: CGRect) {
        for (index, point) in sortedPoints.enumerated() {
            let center = pointPosition(point, rect: rect)
            let radius: CGFloat = selectedIndex == index ? 7 : 5
            let dot = Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.fill(dot, with: .color(.accentColor))
            context.stroke(dot, with: .color(.white.opacity(0.85)), lineWidth: 1)
        }
    }

    private func updatePoint(at index: Int, location: CGPoint, size: CGSize) {
        var sorted = sortedPoints
        guard sorted.indices.contains(index) else { return }
        let rect = pointRect(size: size)
        let temperature = clampedTemperature(at: index, location: location, rect: rect, points: sorted)
        sorted[index] = CurvePoint(
            temperature: temperature,
            rpm: clampedRPM(at: index, proposed: rpm(at: location.y, rect: rect), points: sorted)
        )
        points = sorted
    }

    private func addPoint() {
        let previous = sortedPoints
        guard previous.count < 12 else { return }
        let midTemp = midpointOfWidestGap(in: previous) ?? 50
        guard canInsertTemperature(midTemp, into: previous) else { return }
        let midRPM = FanCurve(points: previous).rpm(for: midTemp, minRPM: Int(minRPM), maxRPM: Int(maxRPM))
        points = (previous + [CurvePoint(temperature: midTemp, rpm: midRPM)])
            .sorted { $0.temperature < $1.temperature }
        selectedIndex = points.firstIndex { $0.temperature == midTemp && $0.rpm == midRPM }
    }

    private func addPoint(at location: CGPoint, size: CGSize) {
        guard points.count < 12 else { return }
        let rect = pointRect(size: size)
        let temperature = temp(at: location.x, rect: rect)
        guard canInsertTemperature(temperature, into: sortedPoints) else { return }
        var updated = (sortedPoints + [CurvePoint(temperature: temperature, rpm: rpm(at: location.y, rect: rect))])
            .sorted { $0.temperature < $1.temperature }
        if let index = updated.firstIndex(where: { $0.temperature == temperature }) {
            updated[index].rpm = clampedRPM(at: index, proposed: updated[index].rpm, points: updated)
        }
        guard let point = updated.first(where: { $0.temperature == temperature }) else { return }
        points = updated
        selectedIndex = points.firstIndex { $0.temperature == point.temperature && $0.rpm == point.rpm }
    }

    private func deleteSelectedPoint() {
        guard let selectedIndex, points.count > 2 else { return }
        var sorted = sortedPoints
        guard sorted.indices.contains(selectedIndex) else { return }
        sorted.remove(at: selectedIndex)
        points = sorted
        self.selectedIndex = nil
    }

    private var sortedPoints: [CurvePoint] {
        points.sorted { $0.temperature < $1.temperature }
    }

    private func canInsertTemperature(_ temperature: Double, into points: [CurvePoint]) -> Bool {
        points.allSatisfy { abs($0.temperature - temperature) >= 1 }
    }

    private func midpointOfWidestGap(in points: [CurvePoint]) -> Double? {
        guard points.count >= 2 else { return nil }
        var bestPair = (points[0], points[1])
        var bestGap = points[1].temperature - points[0].temperature
        for index in 1..<(points.count - 1) {
            let gap = points[index + 1].temperature - points[index].temperature
            if gap > bestGap {
                bestGap = gap
                bestPair = (points[index], points[index + 1])
            }
        }
        return (bestPair.0.temperature + bestPair.1.temperature) / 2
    }

    private func nearestPoint(to location: CGPoint, size: CGSize) -> Int? {
        let rect = pointRect(size: size)
        let distances = sortedPoints.enumerated().map { index, point in
            (index, hypot(pointPosition(point, rect: rect).x - location.x, pointPosition(point, rect: rect).y - location.y))
        }
        guard let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 <= 18 else { return nil }
        return nearest.0
    }

    private func clampedTemperature(at index: Int, location: CGPoint, rect: CGRect, points: [CurvePoint]) -> Double {
        if index == 0 { return tempRange.lowerBound }
        let lower = points[index - 1].temperature + 1
        let upper = index == points.count - 1 ? tempRange.upperBound : points[index + 1].temperature - 1
        return min(max(temp(at: location.x, rect: rect), lower), max(lower, upper))
    }

    private func clampedRPM(at index: Int, proposed: Int, points: [CurvePoint]) -> Int {
        let lower = index == 0 ? Int(minRPM) : points[index - 1].rpm
        let upper = index == points.count - 1 ? Int(maxRPM) : points[index + 1].rpm
        return min(max(proposed, lower), max(lower, upper))
    }

    private func sampledCurvePoints(for curve: FanCurve) -> [CurvePoint] {
        guard let first = curve.points.first, let last = curve.points.last else { return [] }
        let lower = Int(first.temperature.rounded(.down))
        let upper = Int(last.temperature.rounded(.up))
        let temperatures = stride(from: lower, through: upper, by: 1).map(Double.init)
        let samples = temperatures.map { temp in
            CurvePoint(temperature: temp, rpm: curve.rpm(for: temp, minRPM: Int(minRPM), maxRPM: Int(maxRPM)))
        }
        return uniqueCurvePoints(samples + [first, last])
    }

    private func temp(at x: CGFloat, rect: CGRect) -> Double {
        let ratio = min(max((x - rect.minX) / max(rect.width, 1), 0), 1)
        return tempRange.lowerBound + Double(ratio) * (tempRange.upperBound - tempRange.lowerBound)
    }

    private func rpm(at y: CGFloat, rect: CGRect) -> Int {
        let ratio = min(max((rect.maxY - y) / max(rect.height, 1), 0), 1)
        let value = minRPM + Double(ratio) * (maxRPM - minRPM)
        return Int(value.rounded())
    }

    private func pointPosition(_ point: CurvePoint, rect: CGRect) -> CGPoint {
        CGPoint(
            x: xPosition(for: point.temperature, rect: rect),
            y: yPosition(for: Double(point.rpm), rect: rect)
        )
    }

    private func xPosition(for temp: Double, rect: CGRect) -> CGFloat {
        let span = tempRange.upperBound - tempRange.lowerBound
        let ratio = span > 0 ? (temp - tempRange.lowerBound) / span : 0
        let clamped = min(max(ratio, 0), 1)
        return rect.minX + CGFloat(clamped) * rect.width
    }

    private func yPosition(for rpm: Double, rect: CGRect) -> CGFloat {
        let rpmRange = max(maxRPM - minRPM, 1)
        let ratio = (rpm - minRPM) / rpmRange
        let clamped = min(max(ratio, 0), 1)
        return rect.maxY - CGFloat(clamped) * rect.height
    }

    private func plotRect(size: CGSize) -> CGRect {
        CGRect(x: 52, y: 16, width: max(size.width - 68, 1), height: max(size.height - 46, 1))
    }

    /// The drawing rect for curve and points, inset so end/top dots never spill across the plot border.
    private func pointRect(size: CGSize) -> CGRect {
        plotRect(size: size).insetBy(dx: Self.pointInset, dy: Self.pointInset)
    }

    /// Half the largest dot diameter plus its stroke, so selected end-points stay fully inside the border.
    private static let pointInset: CGFloat = 16

    private var gridTemperatures: [Double] {
        let base = stride(from: 0, through: 100, by: 20)
            .map(Double.init)
            .filter { $0 >= tempRange.lowerBound }
        if base.first == tempRange.lowerBound {
            return base
        }
        return [tempRange.lowerBound] + base
    }
}


private func uniqueCurvePoints(_ points: [CurvePoint]) -> [CurvePoint] {
    var unique: [Double: CurvePoint] = [:]
    for point in points {
        unique[point.temperature] = point
    }
    return unique.values.sorted { $0.temperature < $1.temperature }
}