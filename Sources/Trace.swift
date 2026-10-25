import Foundation
import UIKit

/// Lightweight on-device trace log so a tester can paste evidence instead of
/// describing symptoms. Kept deliberately small and synchronous.
enum Trace {
    private static let queue = DispatchQueue(label: "io.xoio.oc.trace")
    private static var url: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("trace.log")
    }

    static func log(_ message: String) {
        let line = "\(Self.stamp()) \(message)\n"
        NSLog("[OC] \(message)")
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    static func tail(_ lines: Int = 60) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "(no trace)" }
        let all = text.split(separator: "\n").map(String.init)
        return all.suffix(lines).joined(separator: "\n")
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Current resident memory in MB — tells a memory kill apart from a logic bug.
    static func residentMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Int(info.resident_size / 1024 / 1024)
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
