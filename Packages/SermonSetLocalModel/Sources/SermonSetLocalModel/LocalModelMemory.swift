import Darwin
import Foundation

enum LocalModelMemory {
    static func available(processMemory: () -> UInt64 = processAvailable,
                          hostMemory: () -> UInt64 = hostAvailable) -> UInt64 {
        #if os(iOS) && !targetEnvironment(simulator)
        // Zero can mean the app exceeded its limit; preserve device refusals.
        return processMemory()
        #else
        // Simulator and Mac processes have no iOS jetsam budget.
        return hostMemory()
        #endif
    }

    private static func processAvailable() -> UInt64 {
        #if os(iOS)
        return UInt64(os_proc_available_memory())
        #else
        return 0
        #endif
    }

    private static func hostAvailable() -> UInt64 {
        #if os(macOS)
        // Preserve the existing Mac evaluation harness estimate.
        return ProcessInfo.processInfo.physicalMemory
        #else
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self(); defer { mach_port_deallocate(mach_task_self_, host) }
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return 0 }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return 0 }
        return (UInt64(stats.free_count) + UInt64(stats.inactive_count)) * UInt64(pageSize)
        #endif
    }
}
