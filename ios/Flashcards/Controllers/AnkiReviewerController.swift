import UIKit
import AVFoundation
import FlashcardsCore

final class AnkiReviewerController: UIViewController, AVSpeechSynthesizerDelegate {
    let state: AnkiAppState, deckID: String
    private var queued: AnkiValue?, question = "", answer = "", css = "", revealed = false, started = Date()
    private var web: AnkiCardWebView!
    private let controls = UIStackView(), counts = UILabel()
    private var audio: AVAudioPlayer?, speech = AVSpeechSynthesizer(), loading = false
    private var typed: AnkiTypedAnswer?
    private var questionTags: [AnkiValue] = [], answerTags: [AnkiValue] = []
    private var answerShownAt: Date?
    private var activeSpeech: AVSpeechUtterance?
    init(state: AnkiAppState, deckID: String, name: String) { self.state = state; self.deckID = deckID; super.init(nibName: nil, bundle: nil); title = name }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        web = AnkiCardWebView(media: state.collection.mediaURL); web.onReveal = { [weak self] in self?.reveal() }
        web.onError = { [weak self] error in
            guard let self else { return }; self.queued = nil
            self.controls.arrangedSubviews.forEach { $0.removeFromSuperview() }
            self.controls.addArrangedSubview(Theme.button("Reload Card", identifier: "ankiReloadCard", action: UIAction { [weak self] _ in self?.next() }))
            self.showError(error)
        }
        speech.delegate = self
        web.onSpeak = { [weak self] question, index in self?.activeSpeech = nil; self?.speech.stopSpeaking(at: .immediate); self?.speak(question: question, index: index) }
        controls.axis = .horizontal; controls.distribution = .fillEqually; controls.spacing = 8
        counts.font = .preferredFont(forTextStyle: .caption1); counts.textColor = .secondaryLabel; counts.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [web, counts, controls]); stack.axis = .vertical; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor), stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), stack.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -10)])
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(actions)); navigationItem.rightBarButtonItem?.accessibilityLabel = "Study Actions"
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setToolbarHidden(true, animated: animated); next() }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); activeSpeech = nil; audio?.stop(); speech.stopSpeaking(at: .immediate); web.evaluateJavaScript("window.__ankiCancelAutoplay?.()") }
    private func next() {
        guard !loading else { return }; loading = true; queued = nil; revealed = false; answerShownAt = nil
        controls.arrangedSubviews.forEach { $0.removeFromSuperview() }; counts.text = "Preparing your next card…"
        let model = state.rwkvModel, precision = state.rwkvPrecision
        let collection = state.collection
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = Result { () -> (AnkiValue, AnkiRenderedCard?, AnkiTypedAnswer?) in
                let queue = try collection.prepareReview(deckID: self.deckID, model: model, precision: precision)
                guard let card = queue["cards"].array.first else { return (queue, nil, nil) }
                let rendered = try collection.render(cardID: card["card"]["id"].string)
                return (queue, rendered, try collection.typedAnswer(cardID: card["card"]["id"].string, question: rendered.question))
            }
            DispatchQueue.main.async {
                self.loading = false
                switch result {
                case .failure(let error): self.counts.text = "Unable to prepare this review."; self.showError(error)
                case .success(let (queue, rendering, typed)):
                    self.typed = typed
                    self.queued = queue["cards"].array.first
                    self.counts.text = "\(queue["newCount"].int) new   ·   \(queue["learningCount"].int) learning   ·   \(queue["reviewCount"].int) review"
                    self.started = Date()
                    if let rendering { self.questionTags = rendering.questionAVTags; self.answerTags = rendering.answerAVTags; self.question = typed?.questionHTML(rendering.question) ?? rendering.question; self.answer = rendering.answer; self.css = rendering.css; self.render(self.question, questionSide: true); self.controls.addArrangedSubview(Theme.button("Show Answer", identifier: "ankiShowAnswer", action: UIAction { [weak self] _ in self?.reveal() })) }
                    else { self.web.show("<h2>You’re done for now</h2><p>Come back when your next cards are due.</p>", css: "", dark: self.traitCollection.userInterfaceStyle == .dark); self.controls.addArrangedSubview(Theme.button("Decks", identifier: "ankiStudyDone", action: UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) })) }
                }
            }
        }
    }
    private func render(_ text: String, questionSide: Bool) {
            var html = text
            activeSpeech = nil; speech.stopSpeaking(at: .immediate)
            let autoplay = !(queued?["reviewConfig"]["disableAutoplay"].bool ?? false)
            for (side, tags) in [("q", questionTags), ("a", answerTags)] {
              for (index, tag) in tags.enumerated() {
                let marker = "[anki:play:\(side):\(index)]"
                guard html.contains(marker) else { continue }
                let shouldPlay = autoplay && (questionSide ? side == "q" : side == "a")
                let playback = shouldPlay ? " data-anki-auto" : ""
                let file = tag["soundOrVideo"].string
                if !file.isEmpty {
                    let escaped = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
                    let video = ["mp4", "webm", "mov"].contains(URL(fileURLWithPath: file).pathExtension.lowercased())
                    let element = video ? "<video controls\(playback) onpointerdown=\"window.__ankiCancelAutoplay?.()\" playsinline src=\"\(escaped)\"></video>" : "<audio controls\(playback) onpointerdown=\"window.__ankiCancelAutoplay?.()\" src=\"\(escaped)\"></audio>"
                    html = html.replacingOccurrences(of: marker, with: element)
                } else if tag["tts"] != .null {
                    html = html.replacingOccurrences(of: marker, with: "<button type=\"button\"\(playback) data-anki-speech=\"tts:\(side):\(index)\" aria-label=\"Replay speech\" onclick=\"window.__ankiCancelAutoplay?.();pycmd('tts:\(side):\(index)')\">▶︎</button>")
                }
              }
            }
            web.show(html, css: css, dark: traitCollection.userInterfaceStyle == .dark, ordinal: queued?["card"]["templateIdx"].int ?? 0)
    }
    private func speak(question: Bool, index: Int) {
        let tags = question ? questionTags : answerTags
        guard tags.indices.contains(index), tags[index]["tts"] != .null else { return }
        let tag = tags[index]["tts"]
        let utterance = AVSpeechUtterance(string: tag["fieldText"].string)
        utterance.voice = AVSpeechSynthesisVoice(language: tag["lang"].string.replacingOccurrences(of: "_", with: "-"))
        let speed = tag["speed"].double > 0 ? tag["speed"].double : 1
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(speed)))
        activeSpeech = utterance
        speech.speak(utterance)
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { speechEnded(utterance) }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { speechEnded(utterance) }
    private func speechEnded(_ utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.activeSpeech === utterance else { return }
            self.activeSpeech = nil; self.web.evaluateJavaScript("window.__ankiSpeechDone?.()")
        }
    }
    private func reveal() {
        guard let queued, !revealed else { return }; revealed = true; answerShownAt = Date()
        if let typed {
            web.evaluateJavaScript("document.getElementById('typeans')?.value || ''") { [weak self] value, error in
                guard let self, self.queued?["card"]["id"] == queued["card"]["id"] else { return }
                do {
                    if let error { throw error }
                    let comparison = try self.state.collection.compareTypedAnswer(typed, provided: value as? String ?? "")
                    self.showAnswer(typed.replacingMarkers(in: self.answer, with: comparison), queued: queued)
                } catch { self.revealed = false; self.showError(error) }
            }
        } else { showAnswer(answer, queued: queued) }
    }
    private func showAnswer(_ html: String, queued: AnkiValue) {
        web.endEditing(true)
        render(html, questionSide: false)
        controls.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let labels = (try? state.collection.backend.call("Scheduler", "DescribeNextStates", queued["states"].object)["vals"].array.map(\.string)) ?? []
        for (i, title) in ["Again", "Hard", "Good", "Easy"].enumerated() {
            let text = (i < labels.count ? labels[i] + "\n" : "") + title
            let button = Theme.button(text, identifier: "ankiRate.\(i + 1)", action: UIAction { [weak self] _ in self?.rate(i + 1) }); button.titleLabel?.numberOfLines = 2; button.titleLabel?.textAlignment = .center
            button.tintColor = [UIColor.systemRed, .systemOrange, .systemGreen, .systemBlue][i]; controls.addArrangedSubview(button)
        }
    }
    private func rate(_ value: Int) { guard let queued else { return }; do { let end = queued["reviewConfig"]["stopTimerOnAnswer"].bool ? (answerShownAt ?? Date()) : Date(); try state.collection.answer(queued: queued, rating: value, seconds: end.timeIntervalSince(started)); next() } catch { showError(error) } }
    @objc private func actions() {
        let sheet = UIAlertController(title: "Study", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Undo Last Answer", style: .default) { [weak self] _ in guard let self else { return }; do { try self.state.collection.undo(); self.next() } catch { self.showError(error) } })
        if let queued {
            sheet.addAction(UIAlertAction(title: "Edit Note", style: .default) { [weak self] _ in guard let self else { return }; do { let note = try self.state.collection.getNote(queued["card"]["noteId"].string); let editor = AnkiEditorController(state: self.state, note: note, deckID: self.deckID); editor.onSave = { [weak self] in self?.next() }; self.presentAnkiEditor(editor) } catch { self.showError(error) } })
            for (title, mode) in [("Suspend Card", 0), ("Bury Card", 2)] { sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in guard let self else { return }; do { try self.state.collection.backend.call("Scheduler", "BuryOrSuspendCards", ["cardIds": .array([queued["card"]["id"]]), "mode": .number(Double(mode))]); self.next() } catch { self.showError(error) } }) }
        }
        sheet.addAction(UIAlertAction(title: "Deck Options", style: .default) { [weak self] _ in guard let self else { return }; self.navigationController?.pushViewController(AnkiOptionsController(state: self.state, deckID: self.deckID), animated: true) })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel)); sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem; present(sheet, animated: true)
    }
    deinit { web?.detach() }
}
