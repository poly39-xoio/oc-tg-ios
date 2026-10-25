import Foundation

/// Uploads the on-device trace so the operator can read it without asking the
/// tester to copy text. Best effort: failures are ignored.
enum DiagUpload {
    static var lastPageState = "(not yet)"
    static var lastTopBar = "(not yet)"

    private static let endpoint = URL(string: "https://poly39.io/oc-diag/run")!
    private static let installId: String = {
        let key = "oc.install.id"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let made = UUID().uuidString.prefix(8)
        UserDefaults.standard.set(String(made), forKey: key)
        return String(made)
    }()

    static func payload(reason: String) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let crashPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/crash.log")
        let crash = (try? String(contentsOf: crashPath, encoding: .utf8)) ?? "(no crash log)"
        return """
        == reason: \(reason) ==
        app: \(version)(\(build)) install: \(installId)
        mem: \(Trace.residentMB())MB
        uptime: \(Int(ProcessInfo.processInfo.systemUptime))s
        == page ==
        \(lastPageState)
        == topbar ==
        \(lastTopBar)
        == crash ==
        \(crash.suffix(1500))
        == trace ==
        \(Trace.tail(120))
        """
    }

    static func upload(reason: String) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("\(installId)-\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")",
                         forHTTPHeaderField: "X-OC-Run")
        request.httpBody = Data(payload(reason: reason).utf8)
        request.timeoutInterval = 20
        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error { NSLog("[OC] diag upload failed: \(error.localizedDescription)") }
        }.resume()
    }
}
