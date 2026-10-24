import UIKit
import WebKit

/// The card document is separate from native study controls so templates can evolve independently.
/// Imported card HTML can contain scripts; this local viewer intentionally disables their execution.
final class CardWebView: WKWebView, WKNavigationDelegate {
    init() {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false
        configuration.defaultWebpagePreferences = preferences
        super.init(frame: .zero, configuration: configuration)
        navigationDelegate = self
        isOpaque = false
        backgroundColor = .systemBackground
        scrollView.backgroundColor = .systemBackground
        accessibilityIdentifier = "reviewCard"
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    func show(html: String, textSize: Double, dark: Bool) {
        let cssURL = Bundle.main.url(forResource: "reviewer", withExtension: "css")
        let css = cssURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "body{text-align:center;font-family:-apple-system}"
        let color = dark ? "#ffffff" : "#000000"
        let background = dark ? "#000000" : "#ffffff"
        let size = min(48, max(12, textSize))
        loadHTMLString("""
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; media-src data:; style-src 'unsafe-inline';"><style>\(css)
        body {font-size:\(size)px;color:\(color);background:\(background)}
        </style></head><body class="\(dark ? "nightMode" : "")"><main id="qa">\(html)</main></body></html>
        """, baseURL: nil)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Never navigate away from the card or launch URLs embedded in imported notes.
        decisionHandler(navigationAction.navigationType == .other && navigationAction.request.url?.scheme == "about" ? .allow : .cancel)
    }
}
