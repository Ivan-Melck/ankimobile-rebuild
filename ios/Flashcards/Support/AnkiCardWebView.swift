import UIKit
import WebKit
import AVFoundation
import FlashcardsCore

/// A separate viewer for real Anki templates: template JavaScript, CSS, local media,
/// audio/video elements and replay commands. Native account credentials never enter it.
final class AnkiCardWebView: WKWebView, WKNavigationDelegate, WKScriptMessageHandler {
    var onReveal: (() -> Void)?
    var onError: ((Error) -> Void)?
    var onLoading: (() -> Void)?
    var onReady: (() -> Void)?
    var onSpeak: ((Bool, Int) -> Void)?
    private var audio: AVAudioPlayer?
    private let media: URL
    private let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("anki-viewer-" + UUID().uuidString, isDirectory: true)
    private var prepared = false
    private var documentURL: URL?
    private var documentReady = false
    private var pendingLoad = false
    private var loadRetries = 0
    private var loadWatchdog: DispatchWorkItem?
    private var loadGeneration = 0
    private var expectedNavigation: WKNavigation?
    init(media: URL) {
        self.media = media
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true; config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(WKUserScript(source: "window.pycmd=function(command){window.webkit.messageHandlers.anki.postMessage(String(command));}; document.addEventListener('click',function(event){if(!event.target.closest('a,input,textarea,button,audio,video,select'))window.pycmd('ans');});", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.addUserScript(WKUserScript(source: """
        (() => {
          let cancelled = false;
          window.__ankiCancelAutoplay = () => {
            cancelled = true; window.__ankiSpeechDone = null;
            document.querySelectorAll('audio,video').forEach(element => element.pause());
          };
          (async () => {
            for (const element of document.querySelectorAll('[data-anki-auto]')) {
              if (cancelled) return;
              if (element.dataset.ankiSpeech) {
                await new Promise(resolve => { window.__ankiSpeechDone = resolve; pycmd(element.dataset.ankiSpeech); });
                window.__ankiSpeechDone = null;
              } else {
                await new Promise(resolve => {
                  element.addEventListener('ended', resolve, {once:true});
                  element.addEventListener('error', resolve, {once:true});
                  element.play().catch(resolve);
                });
              }
            }
          })();
        })();
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        super.init(frame: .zero, configuration: config); config.userContentController.add(self, name: "anki")
        navigationDelegate = self; isOpaque = false; backgroundColor = .systemBackground; accessibilityIdentifier = "ankiReviewCard"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, pendingLoad { loadDocument() }
    }
    func show(_ html: String, css: String, dark: Bool, ordinal: Int = 0) {
        let platform = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        let math = html.contains("\\(") || html.contains("\\[")
        let mathScript = math ? #"<script>window.MathJax={tex:{inlineMath:[['\\(','\\)']],displayMath:[['\\[','\\]']],processEscapes:false,processEnvironments:false,processRefs:false,packages:{'[+]':['noerrors','mathtools'],'[-]':['textmacros']}},startup:{typeset:true}};</script><script defer src=".anki-mathjax.js"></script>"# : ""
        let document = """
        <!doctype html><html class="mobile \(platform)"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><script src=".anki-occlusion.js"></script>\(mathScript)<style>body{font-family:-apple-system;margin:24px;font-size:24px}img,video{max-width:100%;height:auto}body.nightMode{background:#000;color:#fff}button,input{font:inherit}.typeGood{background:#afa;color:#000}.typeBad{background:#faa;color:#000}.typeMissed{background:#ccc;color:#000} \(css)</style></head><body class="card card\(ordinal + 1) mobile \(platform) \(dark ? "nightMode night_mode" : "")"><div id="qa">\(html)</div></body></html>
        """
        do {
            try prepareWorkspace()
            let next = workspace.appendingPathComponent(".review-\(UUID().uuidString).html"), previous = documentURL
            try document.write(to: next, atomically: true, encoding: .utf8)
            loadWatchdog?.cancel(); documentReady = false; loadRetries = 0
            documentURL = next; pendingLoad = true; onLoading?()
            if window != nil { loadDocument() }
            if let previous { try? FileManager.default.removeItem(at: previous) }
        } catch { prepared = false; try? FileManager.default.removeItem(at: workspace); report(error) }
    }
    private func loadDocument() {
        guard window != nil, let expected = documentURL else { pendingLoad = true; return }
        pendingLoad = false; documentReady = false; loadWatchdog?.cancel(); onLoading?()
        loadGeneration += 1; let generation = loadGeneration
        expectedNavigation = loadFileURL(expected, allowingReadAccessTo: workspace)
        let check = DispatchWorkItem { [weak self] in
            guard let self, self.loadGeneration == generation else { return }
            self.validateDocument(expected)
        }
        loadWatchdog = check; DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: check)
    }
    private func validateDocument(_ expected: URL) {
        guard documentURL == expected, !documentReady else { return }
        guard url?.lastPathComponent == expected.lastPathComponent else { recoverDocument(expected); return }
        let generation = loadGeneration
        evaluateJavaScript("Boolean(document.getElementById('qa'))") { [weak self] value, _ in
            guard let self, self.documentURL == expected, self.loadGeneration == generation, !self.documentReady else { return }
            if value as? Bool == true {
                self.documentReady = true; self.loadWatchdog?.cancel(); self.onReady?()
            } else { self.recoverDocument(expected) }
        }
    }
    private func recoverDocument(_ expected: URL) {
        guard documentURL == expected else { return }
        loadWatchdog?.cancel(); documentReady = false; onLoading?()
        guard loadRetries == 0 else {
            report(CollectionError.invalidInput("The card document could not load. Reload the review to try again.")); return
        }
        loadRetries += 1; stopLoading(); pendingLoad = true; loadDocument()
    }
    private func prepareWorkspace() throws {
        guard !prepared else { return }
        let files = FileManager.default
        try files.createDirectory(at: workspace, withIntermediateDirectories: true)
        for source in try files.contentsOfDirectory(at: media, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let target = workspace.appendingPathComponent(source.lastPathComponent)
            do { try files.linkItem(at: source, to: target) }
            catch { try files.copyItem(at: source, to: target) }
        }
        for (resource, name) in [("anki-mathjax-svg", ".anki-mathjax.js"), ("anki-image-occlusion", ".anki-occlusion.js")] {
            guard let source = Bundle.main.url(forResource: resource, withExtension: "js") else { throw CollectionError.invalidInput("The bundled card renderer is missing. Rebuild the app with its resources.") }
            let target = workspace.appendingPathComponent(name)
            if files.fileExists(atPath: target.path) { try files.removeItem(at: target) }
            try files.copyItem(at: source, to: target)
        }
        prepared = true
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let command = message.body as? String else { return }
        if command == "ans", documentReady { onReveal?() }
        else if command.hasPrefix("tts:") {
            let parts = command.split(separator: ":")
            if parts.count == 3, ["q", "a"].contains(String(parts[1])), let index = Int(parts[2]), index >= 0 { onSpeak?(parts[1] == "q", index) }
        }
        else if command.hasPrefix("play:") {
            let file = media.appendingPathComponent(String(command.dropFirst(5))).resolvingSymlinksInPath()
            guard file.deletingLastPathComponent().path == media.resolvingSymlinksInPath().path else { return }
            audio = try? AVAudioPlayer(contentsOf: file); audio?.play()
        }
    }
    func detach() { documentURL = nil; expectedNavigation = nil; pendingLoad = false; loadWatchdog?.cancel(); stopLoading(); configuration.userContentController.removeScriptMessageHandler(forName: "anki"); audio?.stop(); try? FileManager.default.removeItem(at: workspace) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if navigation === expectedNavigation, let expected = documentURL, url?.lastPathComponent == expected.lastPathComponent { validateDocument(expected) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if let expected = documentURL { recoverDocument(expected) }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if navigation === expectedNavigation { report(error) } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if navigation === expectedNavigation { report(error) } }
    private func report(_ error: Error) {
        let error = error as NSError
        if error.code == NSURLErrorCancelled || (error.domain == "WebKitErrorDomain" && error.code == 102) { return }
        onError?(error)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme ?? ""
        if navigationAction.navigationType == .linkActivated, ["https", "http", "mailto"].contains(scheme), let url = navigationAction.request.url { UIApplication.shared.open(url); decisionHandler(.cancel) }
        else if scheme == "file", let url = navigationAction.request.url {
            decisionHandler(url.resolvingSymlinksInPath().path.hasPrefix(workspace.resolvingSymlinksInPath().path + "/") ? .allow : .cancel)
        } else { decisionHandler(scheme == "about" ? .allow : .cancel) }
    }
}
