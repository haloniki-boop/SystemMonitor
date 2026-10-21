import Combine
import Foundation

enum DisplayStyle: String, CaseIterable, Identifiable {
    case analog = "アナログ"
    case digital = "デジタル"
    case gauge = "ゲージ"

    var id: Self { self }
}

@MainActor
final class MonitorModel: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()
    @Published var displayStyle: DisplayStyle {
        didSet { UserDefaults.standard.set(displayStyle.rawValue, forKey: Self.styleKey) }
    }

    private static let styleKey = "displayStyle"
    private let reader = SystemMetricsReader()
    private var timer: AnyCancellable?

    init() {
        let savedStyle = UserDefaults.standard.string(forKey: Self.styleKey)
            .flatMap(DisplayStyle.init(rawValue:))
        displayStyle = savedStyle ?? .digital
        refresh()
        timer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    var menuBarLabel: String {
        "CPU \(Int(snapshot.cpu.used.rounded()))%  MEM \(Int((snapshot.memory.fraction * 100).rounded()))%"
    }

    func refresh() {
        snapshot = reader.read()
    }
}
