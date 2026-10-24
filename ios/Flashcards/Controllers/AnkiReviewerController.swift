import UIKit
import AVFoundation
import FlashcardsCore

final class AnkiReviewerController: UIViewController {
    let state: AnkiAppState, deckID: String
    private var queued: AnkiValue?, question = "", answer = "", css = "", revealed = false, started = Date()
    private var web: AnkiCardWebView!
    private let controls = UIStackView(), counts = UILabel()
    private var audio: AVAudioPlayer?, speech = AVSpeechSynthesizer(), loading = false
    init(state: AnkiAppState, deckID: String, name: String) { self.state = state; self.deckID = deckID; super.init(nibName: nil, bundle: nil); title = name }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        web = AnkiCardWebView(media: state.collection.mediaURL); web.onReveal = { [weak self] in self?.reveal() }
        controls.axis = .horizontal; controls.distribution = .fillEqually; controls.spacing = 8
        counts.font = .preferredFont(forTextStyle: .caption1); counts.textColor = .secondaryLabel; counts.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [web, counts, controls]); stack.axis = .vertical; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor), stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)])
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(actions)); navigationItem.rightBarButtonItem?.accessibilityLabel = "Study Actions"
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setToolbarHidden(true, animated: animated); next() }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); audio?.stop(); speech.stopSpeaking(at: .immediate) }
    private func next() {
        guard !loading else { return }; loading = true; queued = nil; revealed = false
        controls.arrangedSubviews.forEach { $0.removeFromSuperview() }; counts.text = "Preparing your next card…"
        let model = state.rwkvModel, precision = state.rwkvPrecision
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = Result { () -> (AnkiValue, (question: String, answer: String, css: String)?) in
                let queue = try self.state.collection.prepareReview(deckID: self.deckID, model: model, precision: precision)
                guard let card = queue["cards"].array.first else { return (queue, nil) }
                return (queue, try self.state.collection.render(cardID: card["card"]["id"].string))
            }
            DispatchQueue.main.async {
                self.loading = false
                switch result {
                case .failure(let error): self.counts.text = "Unable to prepare this review."; self.showError(error)
                case .success(let (queue, rendering)):
                    self.queued = queue["cards"].array.first
                    self.counts.text = "\(queue["newCount"].int) new   ·   \(queue["learningCount"].int) learning   ·   \(queue["reviewCount"].int) review"
                    self.started = Date()
                    if let rendering { self.question = rendering.question; self.answer = rendering.answer; self.css = rendering.css; self.render(self.question, questionSide: true); self.controls.addArrangedSubview(Theme.button("Show Answer", identifier: "ankiShowAnswer", action: UIAction { [weak self] _ in self?.reveal() })) }
                    else { self.web.show("<h2>You’re done for now</h2><p>Come back when your next cards are due.</p>", css: "", dark: self.traitCollection.userInterfaceStyle == .dark); self.controls.addArrangedSubview(Theme.button("Decks", identifier: "ankiStudyDone", action: UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) })) }
                }
            }
        }
    }
    private func render(_ text: String, questionSide: Bool) {
        do {
            let av = try state.collection.backend.call("CardRendering", "ExtractAvTags", ["text": .string(text), "questionSide": .bool(questionSide)])
            var html = av["text"].string
            for tag in av["avTags"].array {
                let file = tag["soundOrVideo"].string
                if !file.isEmpty {
                    let escaped = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
                    let video = ["mp4", "webm", "mov"].contains(URL(fileURLWithPath: file).pathExtension.lowercased())
                    html += video ? "<video controls autoplay playsinline src=\"\(escaped)\"></video>" : "<audio controls autoplay src=\"\(escaped)\"></audio>"
                } else if tag["tts"] != .null {
                    let utterance = AVSpeechUtterance(string: tag["tts"]["fieldText"].string); utterance.voice = AVSpeechSynthesisVoice(language: tag["tts"]["lang"].string); speech.speak(utterance)
                }
            }
            web.show(html, css: css, dark: traitCollection.userInterfaceStyle == .dark)
        } catch { showError(error) }
    }
    private func reveal() {
        guard let queued, !revealed else { return }; revealed = true; render(answer, questionSide: false)
        controls.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let labels = (try? state.collection.backend.call("Scheduler", "DescribeNextStates", queued["states"].object)["vals"].array.map(\.string)) ?? []
        for (i, title) in ["Again", "Hard", "Good", "Easy"].enumerated() {
            let text = (i < labels.count ? labels[i] + "\n" : "") + title
            let button = Theme.button(text, identifier: "ankiRate.\(i + 1)", action: UIAction { [weak self] _ in self?.rate(i + 1) }); button.titleLabel?.numberOfLines = 2; button.titleLabel?.textAlignment = .center
            button.tintColor = [UIColor.systemRed, .systemOrange, .systemGreen, .systemBlue][i]; controls.addArrangedSubview(button)
        }
    }
    private func rate(_ value: Int) { guard let queued else { return }; do { try state.collection.answer(queued: queued, rating: value, seconds: Date().timeIntervalSince(started)); next() } catch { showError(error) } }
    @objc private func actions() {
        let sheet = UIAlertController(title: "Study", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Undo Last Answer", style: .default) { [weak self] _ in guard let self else { return }; do { try self.state.collection.undo(); self.next() } catch { self.showError(error) } })
        if let queued {
            sheet.addAction(UIAlertAction(title: "Edit Note", style: .default) { [weak self] _ in guard let self else { return }; do { let note = try self.state.collection.getNote(queued["card"]["noteId"].string); self.present(UINavigationController(rootViewController: AnkiEditorController(state: self.state, note: note, deckID: self.deckID)), animated: true) } catch { self.showError(error) } })
            for (title, mode) in [("Suspend Card", 0), ("Bury Card", 2)] { sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in guard let self else { return }; do { try self.state.collection.backend.call("Scheduler", "BuryOrSuspendCards", ["cardIds": .array([queued["card"]["id"]]), "mode": .number(Double(mode))]); self.next() } catch { self.showError(error) } }) }
        }
        sheet.addAction(UIAlertAction(title: "Deck Options", style: .default) { [weak self] _ in guard let self else { return }; self.navigationController?.pushViewController(AnkiOptionsController(state: self.state, deckID: self.deckID), animated: true) })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel)); sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem; present(sheet, animated: true)
    }
    deinit { web?.detach() }
}
