import SwiftUI

struct MetricDescriptor {
    let title: String
    let symbol: String
    let value: MetricValue
    let color: Color
    let format: (Double) -> String

    var percent: Int { Int((value.fraction * 100).rounded()) }
    var displayColor: Color { value.isLowRemaining ? .red : color }
}

struct MetricView: View {
    let metric: MetricDescriptor
    let style: DisplayStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(metric.title, systemImage: metric.symbol)
                .font(.headline)

            Group {
                switch style {
                case .analog:
                    AnalogDial(metric: metric)
                case .digital:
                    DigitalReadout(metric: metric)
                case .gauge:
                    CircularGauge(metric: metric)
                }
            }
            .frame(maxWidth: .infinity)

            DetailsGrid(metric: metric)
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct DigitalReadout: View {
    let metric: MetricDescriptor

    var body: some View {
        VStack(spacing: 1) {
            Text("\(metric.percent)")
                .font(.system(size: 50, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(metric.displayColor)
            Text("% 使用中")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: 92)
    }
}

private struct CircularGauge: View {
    let metric: MetricDescriptor

    var body: some View {
        ZStack {
            Circle()
                .stroke(metric.displayColor.opacity(0.16), lineWidth: 13)
            Circle()
                .trim(from: 0, to: metric.value.fraction)
                .stroke(metric.displayColor, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(metric.percent)%")
                    .font(.title2.bold().monospacedDigit())
                Text("使用中").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 94, height: 94)
    }
}

private struct AnalogDial: View {
    let metric: MetricDescriptor

    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height * 0.76)
                let radius = min(size.width * 0.42, size.height * 0.69)

                for tick in 0...10 {
                    let angle = Double.pi * (1 + Double(tick) / 10)
                    let outer = point(center: center, radius: radius, angle: angle)
                    let inner = point(center: center, radius: radius - (tick % 5 == 0 ? 10 : 6), angle: angle)
                    var path = Path()
                    path.move(to: inner)
                    path.addLine(to: outer)
                    context.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: tick % 5 == 0 ? 2 : 1)
                }

                let endAngle = Double.pi * (1 + metric.value.fraction)
                var arc = Path()
                arc.addArc(center: center, radius: radius - 15, startAngle: .radians(.pi), endAngle: .radians(endAngle), clockwise: false)
                context.stroke(arc, with: .color(metric.displayColor), style: StrokeStyle(lineWidth: 5, lineCap: .round))

                let needleEnd = point(center: center, radius: radius - 20, angle: endAngle)
                var needle = Path()
                needle.move(to: center)
                needle.addLine(to: needleEnd)
                context.stroke(needle, with: .color(.primary), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(metric.displayColor))
            }
            Text("\(metric.percent)%")
                .font(.headline.monospacedDigit())
                .offset(y: 34)
        }
        .frame(height: 100)
    }

    private func point(center: CGPoint, radius: Double, angle: Double) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
}

private struct DetailsGrid: View {
    let metric: MetricDescriptor

    var body: some View {
        HStack(spacing: 0) {
            item("使用量", metric.format(metric.value.used))
            Divider().frame(height: 32)
            item("残量", metric.format(metric.value.remaining), warning: metric.value.isLowRemaining)
            Divider().frame(height: 32)
            item("総量", metric.format(metric.value.total))
        }
    }

    private func item(_ title: String, _ value: String, warning: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(warning ? .red : .primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
