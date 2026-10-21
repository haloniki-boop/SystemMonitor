import Darwin
import Foundation

struct MetricValue: Equatable {
    let used: Double
    let remaining: Double
    let total: Double

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(used / total, 0), 1)
    }

    var remainingFraction: Double {
        guard total > 0 else { return 0 }
        return min(max(remaining / total, 0), 1)
    }

    var isLowRemaining: Bool {
        total > 0 && remainingFraction <= 0.2
    }
}

struct SystemSnapshot: Equatable {
    var cpu = MetricValue(used: 0, remaining: 100, total: 100)
    var memory = MetricValue(used: 0, remaining: 0, total: 0)
    var updatedAt = Date()
}

struct CPUTicks {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64

    var total: UInt64 { user &+ system &+ idle &+ nice }
    var busy: UInt64 { user &+ system &+ nice }
}

enum MetricsMath {
    static func cpuUsage(previous: CPUTicks, current: CPUTicks) -> Double {
        let totalDelta = current.total &- previous.total
        let busyDelta = current.busy &- previous.busy
        guard totalDelta > 0 else { return 0 }
        return min(max(Double(busyDelta) / Double(totalDelta) * 100, 0), 100)
    }

    static func bytesLabel(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(max(0, bytes)))
    }
}

final class SystemMetricsReader {
    private var previousTicks: CPUTicks?

    init() {
        previousTicks = readCPUTicks()
    }

    func read() -> SystemSnapshot {
        let currentTicks = readCPUTicks()
        let cpuUsed: Double
        if let previousTicks, let currentTicks {
            cpuUsed = MetricsMath.cpuUsage(previous: previousTicks, current: currentTicks)
        } else {
            cpuUsed = 0
        }
        previousTicks = currentTicks

        let totalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        let usedMemory = min(readUsedMemoryBytes() ?? 0, totalMemory)

        return SystemSnapshot(
            cpu: MetricValue(used: cpuUsed, remaining: max(0, 100 - cpuUsed), total: 100),
            memory: MetricValue(
                used: usedMemory,
                remaining: max(0, totalMemory - usedMemory),
                total: totalMemory
            ),
            updatedAt: Date()
        )
    }

    private func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }

        return withUnsafePointer(to: &info.cpu_ticks) { pointer in
            pointer.withMemoryRebound(to: UInt32.self, capacity: Int(CPU_STATE_MAX)) { ticks in
                CPUTicks(
                    user: UInt64(ticks[Int(CPU_STATE_USER)]),
                    system: UInt64(ticks[Int(CPU_STATE_SYSTEM)]),
                    idle: UInt64(ticks[Int(CPU_STATE_IDLE)]),
                    nice: UInt64(ticks[Int(CPU_STATE_NICE)])
                )
            }
        }
    }

    private func readUsedMemoryBytes() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let status = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }

        let pages = UInt64(stats.active_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)
        return Double(pages) * Double(vm_kernel_page_size)
    }
}
