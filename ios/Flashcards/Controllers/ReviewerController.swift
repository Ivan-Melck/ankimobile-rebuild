import UIKit
import FlashcardsCore

final class ReviewerController: UIViewController {
    private let model: AppModel
    private let deck: Deck
    private var current: StudyCard?
    private var revealed = false
    private let web = CardWebView()
    private let controls = UIStackView()
    private let counts = UILabel()
    private var shownHTML = ""
    private var startedAt = Date()

    init(model: AppModel, deck: Deck) { self.model = model; self.deck = deck; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(model:deck:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = deck.name
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(more))
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Study Actions"
        counts.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        counts.textAlignment = .center
        counts.accessibilityIdentifier = "studyCounts"
        controls.axis = .horizontal; controls.distribution = .fillEqually; controls.spacing = 4
        [counts, web, controls].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        NSLayoutConstraint.activate([
            counts.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            counts.leadingAnchor.constraint(equalTo: view.leadingAnchor), counts.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            counts.heightAnchor.constraint(equalToConstant: 22),
            web.topAnchor.constraint(equalTo: counts.bottomAnchor, constant: 4), web.leadingAnchor.constraint(equalTo: view.leadingAnchor), web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -8),
            controls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            controls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            controls.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
        nextCard()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
        if let current = current { currentFromStore(current.card.id) }
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        render(shownHTML)
    }
    private func currentFromStore(_ id: UUID) {
        if let updated = model.store.search("").first(where: { $0.card.id == id }) {
            current = updated; render(revealed ? updated.answerHTML : updated.questionHTML)
        } else { nextCard() }
    }
    private func render(_ html: String) {
        shownHTML = html
        web.show(html: html, textSize: model.textSize, dark: traitCollection.userInterfaceStyle == .dark)
    }
    private func nextCard() {
        current = model.store.studyQueue(deckID: deck.id).first
        revealed = false
        startedAt = Date()
        let values = model.store.deckCounts(deckID: deck.id)
        let text = NSMutableAttributedString(string: "")
        for (index, pair) in [(values.new, Theme.new), (values.learning, Theme.learning), (values.review, Theme.review)].enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "   ")) }
            text.append(NSAttributedString(string: String(pair.0), attributes: [.foregroundColor: pair.1]))
        }
        counts.attributedText = text
        controls.arrangedSubviews.forEach { controls.removeArrangedSubview($0); $0.removeFromSuperview() }
        if let current = current {
            render(current.questionHTML)
            controls.addArrangedSubview(Theme.button("Show Answer", identifier: "showAnswer", action: UIAction { [weak self] _ in self?.showAnswer() }))
        } else {
            render("<h2>Congratulations!</h2><p>You have finished this deck for now.</p><p>Come back later or add new cards to continue.</p>")
            controls.addArrangedSubview(Theme.button("Decks", identifier: "studyDone", action: UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) }))
        }
    }
    private func showAnswer() {
        guard let current = current else { return }
        revealed = true; render(current.answerHTML)
        controls.arrangedSubviews.forEach { controls.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (name, rating, color) in [("Again", ReviewRating.again, UIColor.systemRed), ("Hard", .hard, .systemGray), ("Good", .good, .systemGreen), ("Easy", .easy, .systemBlue)] {
            let button = Theme.button(name, identifier: "rate.\(name.lowercased())", action: UIAction { [weak self] _ in self?.rate(rating) })
            button.setTitleColor(color, for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
            controls.addArrangedSubview(button)
        }
    }
    private func rate(_ rating: ReviewRating) {
        guard let card = current else { return }
        do { _ = try model.store.answer(cardID: card.card.id, rating: rating, durationSeconds: max(0, Date().timeIntervalSince(startedAt))); nextCard() }
        catch { showError(error) }
    }
    @objc private func more() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        if let current = current {
            sheet.addAction(UIAlertAction(title: "Edit Note", style: .default) { [weak self] _ in
                guard let self = self else { return }
                let editor = EditorController(model: self.model, note: current.note, deckID: current.deck.id)
                editor.onSave = { [weak self] in self?.currentFromStore(current.card.id) }
                self.present(UINavigationController(rootViewController: editor), animated: true)
            })
            sheet.addAction(UIAlertAction(title: "Bury Card", style: .default) { [weak self] _ in
                guard let self = self else { return }
                do { try self.model.store.bury(cardID: current.card.id, until: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!); self.nextCard() } catch { self.showError(error) }
            })
            sheet.addAction(UIAlertAction(title: "Suspend Card", style: .default) { [weak self] _ in
                guard let self = self else { return }
                do { try self.model.store.setSuspended(cardID: current.card.id, suspended: true); self.nextCard() } catch { self.showError(error) }
            })
        }
        sheet.addAction(UIAlertAction(title: "Undo Last Answer", style: .default) { [weak self] _ in
            guard let self = self else { return }
            do { try self.model.store.undoLastReview(); self.nextCard() } catch { self.showError(error) }
        })
        sheet.addAction(UIAlertAction(title: "Deck Options", style: .default) { [weak self] _ in
            guard let self = self else { return }; self.navigationController?.pushViewController(DeckOptionsController(model: self.model, deck: self.deck), animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Statistics", style: .default) { [weak self] _ in
            guard let self = self else { return }; self.navigationController?.pushViewController(StatisticsController(model: self.model, deckID: self.deck.id), animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(sheet, animated: true)
    }
}
