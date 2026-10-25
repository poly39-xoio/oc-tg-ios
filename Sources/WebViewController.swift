import UIKit
import WebKit

final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    private var webView: WKWebView!
    private var server: LocalWebServer?
    private let spinner = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()

    private let background = UIColor(red: 0.35, green: 0.41, blue: 0.47, alpha: 1.0) // #5A6A78-ish slate
    /// Matches the skin's top bar (#3F4A54) so the status-bar strip blends in.
    private let topBarColor = UIColor(red: 0.247, green: 0.290, blue: 0.329, alpha: 1.0)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = background
        setupSpinner()

        let webRoot = (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("web", isDirectory: true)
        let server = LocalWebServer(root: webRoot)
        do {
            let port = try server.start()
            self.server = server
            let url = URL(string: "http://127.0.0.1:\(port)/")!
            setupWebView()
            webView.load(URLRequest(url: url))
        } catch {
            NSLog("[OC] failed to start local server: \(error.localizedDescription)")
            showFatal("無法啟動本機服務 / Local server failed")
        }
    }

    deinit {
        server?.stop()
    }

    // MARK: - UI

    private func setupSpinner() {
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "OC"
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16)
        ])
        spinner.startAnimating()
    }

    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        if #available(iOS 14.0, *) {
            configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        }

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = true
        webView.isOpaque = false
        webView.backgroundColor = background
        webView.scrollView.backgroundColor = background
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        // Keep the web content below the notch/status bar: the Telegram header's
        // back button sat too close to the screen edge when the page ran full-bleed.
        let statusBackground = UIView()
        statusBackground.backgroundColor = topBarColor
        statusBackground.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(statusBackground, belowSubview: webView)

        NSLayoutConstraint.activate([
            statusBackground.topAnchor.constraint(equalTo: view.topAnchor),
            statusBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBackground.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),

            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func showFatal(_ message: String) {
        spinner.stopAnimating()
        statusLabel.text = message
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logPageState()
        UIView.animate(withDuration: 0.2) {
            self.spinner.alpha = 0
            self.statusLabel.alpha = 0
        } completion: { _ in
            self.spinner.stopAnimating()
            self.spinner.isHidden = true
            self.statusLabel.isHidden = true
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("[OC] didFail: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("[OC] didFailProvisional: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host ?? ""

        if host == "127.0.0.1" || host == "localhost" {
            decisionHandler(.allow)
            return
        }

        if scheme == "http" || scheme == "https" {
            // External links (news, t.me previews, oauth) open in Safari.
            if navigationAction.targetFrame == nil {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
            return
        }

        if scheme == "tel" || scheme == "mailto" || scheme == "sms" || scheme == "tg" {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        decisionHandler(.cancel)
    }

    /// Console evidence for CI smoke tests: what the web app actually rendered.
    private func logPageState() {
        let js = """
        JSON.stringify({
          title: document.title,
          href: location.href,
          hasSubtle: !!(window.crypto && window.crypto.subtle),
          isSecureContext: window.isSecureContext,
          hasWasm: typeof WebAssembly === 'object',
          bodyLen: document.body ? document.body.innerText.length : -1,
          text: document.body ? document.body.innerText.replace(/\\s+/g, ' ').slice(0, 180) : ''
        })
        """
        webView.evaluateJavaScript(js) { result, error in
            if let error = error {
                NSLog("[OC] pageState error: \(error.localizedDescription)")
            } else {
                NSLog("[OC] pageState: \(String(describing: result))")
            }
        }
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if let host = url.host, host == "127.0.0.1" || host == "localhost" {
                webView.load(navigationAction.request)
            } else {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        present(alert, animated: true)
    }
}
