import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NSSetUncaughtExceptionHandler { exception in
            let text = "exception \(exception.name.rawValue): \(exception.reason ?? "-")\n" +
                exception.callStackSymbols.joined(separator: "\n")
            if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? text.write(to: dir.appendingPathComponent("crash.log"), atomically: true, encoding: .utf8)
            }
        }
        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP] {
            signal(sig, ocCrashSignalHandler)
        }
        Trace.log("didFinishLaunching")

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = WebViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

// Crash evidence for the on-device diagnostics sheet.
func ocCrashSignalHandler(_ sig: Int32) {
    let stack = Thread.callStackSymbols.joined(separator: "\n")
    let line = "signal=\(sig)\n\(stack)\n"
    if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
        try? line.write(to: dir.appendingPathComponent("crash.log"), atomically: true, encoding: .utf8)
    }
    signal(sig, SIG_DFL)
    raise(sig)
}
