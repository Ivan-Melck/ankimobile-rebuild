import UIKit
import WebKit
import AVFoundation
import FlashcardsCore

private final class AnkiMediaHandler: NSObject, WKURLSchemeHandler {
    let directory: URL
    init(directory: URL) { self.directory = directory.resolvingSymlinksInPath() }
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        do {
            guard let url = urlSchemeTask.request.url else { throw URLError(.badURL) }
            let name = url.lastPathComponent
            let file = directory.appendingPathComponent(name).resolvingSymlinksInPath()
            guard !name.isEmpty, file.deletingLastPathComponent().path == directory.path else { throw URLError(.noPermissionsToReadFile) }
            let data = try Data(contentsOf: file)
            let types = ["jpg":"image/jpeg", "jpeg":"image/jpeg", "png":"image/png", "svg":"image/svg+xml", "gif":"image/gif", "webp":"image/webp", "mp3":"audio/mpeg", "mp4":"video/mp4", "wav":"audio/wav", "ogg":"audio/ogg", "css":"text/css", "js":"application/javascript", "woff":"font/woff", "woff2":"font/woff2", "ttf":"font/ttf"]
            urlSchemeTask.didReceive(URLResponse(url: url, mimeType: types[file.pathExtension.lowercased()] ?? "application/octet-stream", expectedContentLength: data.count, textEncodingName: nil)); urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

/// A separate viewer for real Anki templates: template JavaScript, CSS, local media,
/// audio/video elements and replay commands. Native account credentials never enter it.
final class AnkiCardWebView: WKWebView, WKNavigationDelegate, WKScriptMessageHandler {
    var onReveal: (() -> Void)?
    var onError: ((Error) -> Void)?
    private var audio: AVAudioPlayer?
    private let media: URL
    init(media: URL) {
        self.media = media
        let config = WKWebViewConfiguration(); config.setURLSchemeHandler(AnkiMediaHandler(directory: media), forURLScheme: "anki-media")
        config.allowsInlineMediaPlayback = true; config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(WKUserScript(source: "window.pycmd=function(command){window.webkit.messageHandlers.anki.postMessage(String(command));}; document.addEventListener('click',function(event){if(!event.target.closest('a,input,textarea,button,audio,video,select'))window.pycmd('ans');});", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        super.init(frame: .zero, configuration: config); config.userContentController.add(self, name: "anki")
        navigationDelegate = self; isOpaque = false; backgroundColor = .systemBackground; accessibilityIdentifier = "ankiReviewCard"
    }
    required init?(coder: NSCoder) { fatalError() }
    func show(_ html: String, css: String, dark: Bool, ordinal: Int = 0) {
        let platform = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        loadHTMLString("""
        <!doctype html><html class="mobile \(platform)"><head><base href="anki-media://collection/"><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{font-family:-apple-system;margin:24px;font-size:24px}img,video{max-width:100%;height:auto}body.nightMode{background:#000;color:#fff}button,input{font:inherit}.typeGood{background:#afa;color:#000}.typeBad{background:#faa;color:#000}.typeMissed{background:#ccc;color:#000} \(css)</style></head><body class="card card\(ordinal + 1) mobile \(platform) \(dark ? "nightMode night_mode" : "")"><div id="qa">\(html)</div></body></html>
        """, baseURL: nil)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let command = message.body as? String else { return }
        if command == "ans" { onReveal?() }
        else if command.hasPrefix("play:") {
            let file = media.appendingPathComponent(String(command.dropFirst(5))).resolvingSymlinksInPath()
            guard file.deletingLastPathComponent().path == media.resolvingSymlinksInPath().path else { return }
            audio = try? AVAudioPlayer(contentsOf: file); audio?.play()
        }
    }
    func detach() { stopLoading(); configuration.userContentController.removeScriptMessageHandler(forName: "anki"); audio?.stop() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error) }
    private func report(_ error: Error) {
        let error = error as NSError
        if error.code == NSURLErrorCancelled || (error.domain == "WebKitErrorDomain" && error.code == 102) { return }
        onError?(error)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme ?? ""
        if navigationAction.navigationType == .linkActivated, ["https", "http", "mailto"].contains(scheme), let url = navigationAction.request.url { UIApplication.shared.open(url); decisionHandler(.cancel) }
        else { decisionHandler(["about", "anki-media"].contains(scheme) ? .allow : .cancel) }
    }
}
