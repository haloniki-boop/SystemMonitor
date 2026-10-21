import AppKit
import Combine
import SwiftUI

@MainActor
enum ActivityMonitorLauncher {
    static func open() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}

struct MonitorPanel: View {
    @ObservedObject var model: MonitorModel

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("システムモニター").font(.title3.bold())
                Spacer()
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("今すぐ更新")
                Menu {
                    Button("アクティビティモニタを開く") {
                        ActivityMonitorLauncher.open()
                    }
                    Divider()
                    Button("SystemMonitorを終了") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("メニュー")
            }

            Picker("表示", selection: $model.displayStyle) {
                ForEach(DisplayStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            MetricView(
                metric: MetricDescriptor(
                    title: "CPU",
                    symbol: "cpu",
                    value: model.snapshot.cpu,
                    color: .blue,
                    format: { String(format: "%.0f%%", $0) }
                ),
                style: model.displayStyle
            )

            MetricView(
                metric: MetricDescriptor(
                    title: "メモリ",
                    symbol: "memorychip",
                    value: model.snapshot.memory,
                    color: .purple,
                    format: MetricsMath.bytesLabel
                ),
                style: model.displayStyle
            )

            HStack {
                Spacer()
                Button("終了") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .font(.caption)
        }
        .padding(16)
        .frame(width: 350)
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let model: MonitorModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()
    private var pendingSingleClick: DispatchWorkItem?

    init(model: MonitorModel) {
        self.model = model
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MonitorPanel(model: model))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp])
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
        }

        model.$snapshot
            .combineLatest(model.$displayStyle)
            .sink { [weak self] snapshot, style in
                self?.updateStatusItem(snapshot: snapshot, style: style)
            }
            .store(in: &subscriptions)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        pendingSingleClick?.cancel()

        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
            popover.performClose(nil)
            ActivityMonitorLauncher.open()
            return
        }

        let work = DispatchWorkItem { [weak self, weak sender] in
            guard let self, let sender else { return }
            if self.popover.isShown {
                self.popover.performClose(nil)
            } else {
                self.model.refresh()
                self.popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            }
        }
        pendingSingleClick = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func updateStatusItem(snapshot: SystemSnapshot, style: DisplayStyle) {
        let image = StatusItemImage.make(snapshot: snapshot, style: style)
        statusItem.length = image.size.width + 8
        statusItem.button?.image = image
        statusItem.button?.toolTip = "CPU \(Int(snapshot.cpu.used.rounded()))%・メモリ \(Int((snapshot.memory.fraction * 100).rounded()))%\nダブルクリック：アクティビティモニタ"
        statusItem.button?.setAccessibilityLabel("CPUとメモリの使用状況")
        statusItem.button?.setAccessibilityValue(model.menuBarLabel)
    }
}

@MainActor
private enum StatusItemImage {
    static func make(snapshot: SystemSnapshot, style: DisplayStyle) -> NSImage {
        let size = style == .digital ? NSSize(width: 128, height: 22) : NSSize(width: 94, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        switch style {
        case .digital:
            drawDigital(snapshot)
        case .analog:
            drawWhiteBackground(in: size)
            drawAnalog(snapshot)
        case .gauge:
            drawWhiteBackground(in: size)
            drawGauges(snapshot)
        }
        image.isTemplate = false
        return image
    }

    private static func color(for metric: MetricValue, normal: NSColor) -> NSColor {
        metric.isLowRemaining ? .systemRed : normal
    }

    private static func drawWhiteBackground(in size: NSSize) {
        let background = NSBezierPath(
            roundedRect: NSRect(x: 1, y: 1, width: size.width - 2, height: size.height - 2),
            xRadius: 4,
            yRadius: 4
        )
        NSColor.white.setFill()
        background.fill()
    }

    private static func drawDigital(_ snapshot: SystemSnapshot) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        "CPU \(Int(snapshot.cpu.used.rounded()))%".draw(at: NSPoint(x: 2, y: 5), withAttributes: [
            .font: font,
            .foregroundColor: color(for: snapshot.cpu, normal: .white)
        ])
        "MEM \(Int((snapshot.memory.fraction * 100).rounded()))%".draw(at: NSPoint(x: 65, y: 5), withAttributes: [
            .font: font,
            .foregroundColor: color(for: snapshot.memory, normal: .white)
        ])
    }

    private static func drawAnalog(_ snapshot: SystemSnapshot) {
        drawDial(label: "C", metric: snapshot.cpu, centerX: 23, normal: .systemBlue)
        drawDial(label: "M", metric: snapshot.memory, centerX: 70, normal: .systemPurple)
    }

    private static func drawDial(label: String, metric: MetricValue, centerX: CGFloat, normal: NSColor) {
        let center = NSPoint(x: centerX, y: 4)
        let radius: CGFloat = 12
        let strokeColor = color(for: metric, normal: normal)
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 180)
        arc.lineWidth = 2
        strokeColor.setStroke()
        arc.stroke()

        let angle = CGFloat.pi * (1 - metric.fraction)
        let needle = NSBezierPath()
        needle.move(to: center)
        needle.line(to: NSPoint(x: center.x + cos(angle) * 10, y: center.y + sin(angle) * 10))
        needle.lineWidth = 1.5
        strokeColor.setStroke()
        needle.stroke()

        "\(label)\(Int((metric.fraction * 100).rounded()))".draw(at: NSPoint(x: centerX - 12, y: 8), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium),
            .foregroundColor: strokeColor
        ])
    }

    private static func drawGauges(_ snapshot: SystemSnapshot) {
        drawGauge(label: "C", metric: snapshot.cpu, centerX: 19, normal: .systemBlue)
        drawGauge(label: "M", metric: snapshot.memory, centerX: 64, normal: .systemPurple)
    }

    private static func drawGauge(label: String, metric: MetricValue, centerX: CGFloat, normal: NSColor) {
        let center = NSPoint(x: centerX, y: 11)
        let radius: CGFloat = 8
        let strokeColor = color(for: metric, normal: normal)

        let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        track.lineWidth = 2.5
        NSColor.secondaryLabelColor.withAlphaComponent(0.2).setStroke()
        track.stroke()

        let progress = NSBezierPath()
        progress.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * metric.fraction, clockwise: true)
        progress.lineWidth = 2.5
        strokeColor.setStroke()
        progress.stroke()

        label.draw(at: NSPoint(x: centerX - 3, y: 6), withAttributes: [
            .font: NSFont.systemFont(ofSize: 7, weight: .bold),
            .foregroundColor: strokeColor
        ])
        "\(Int((metric.fraction * 100).rounded()))%".draw(at: NSPoint(x: centerX + 11, y: 6), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium),
            .foregroundColor: strokeColor
        ])
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = StatusItemController(model: MonitorModel())
    }
}

@main
struct SystemMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
