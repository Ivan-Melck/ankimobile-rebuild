import UIKit
import FlashcardsCore

final class EditorController: UITableViewController {
    private let model: AppModel
    private let note: Note?
    private var deckID: UUID?
    private var kind: NoteKind
    private let front = UITextView()
    private let back = UITextView()
    private let tags = UITextField()
    var onSave: (() -> Void)?

    init(model: AppModel, note: Note?, deckID: UUID?) {
        self.model = model; self.note = note; self.deckID = deckID; self.kind = note?.kind ?? .basic
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("Use init(model:note:deckID:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = note == nil ? "Add" : "Edit Note"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: note == nil ? "Add" : "Save", style: .done, target: self, action: #selector(save))
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "saveNote"
        front.text = note?.front ?? ""; back.text = note?.back ?? ""; tags.text = note?.tags.joined(separator: " ") ?? ""
        for (field, identifier) in [(front, "noteFront"), (back, "noteBack")] {
            field.font = .preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
            field.isScrollEnabled = true
            field.accessibilityIdentifier = identifier
            field.autocorrectionType = .default
        }
        tags.placeholder = "space-separated tags"
        tags.autocapitalizationType = .none
        tags.autocorrectionType = .no
        tags.accessibilityIdentifier = "noteTags"
        tableView.keyboardDismissMode = .interactive
    }
    @objc private func cancel() { dismiss(animated: true) }
    @objc private func save() {
        guard let deckID = deckID else { showMessage("Select a Deck", "Create a deck from Tools before adding a note."); return }
        do {
            let tagList = (tags.text ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if let note = note {
                _ = try model.store.updateNote(id: note.id, front: front.text, back: back.text, tags: tagList, kind: kind)
            } else {
                _ = try model.store.addNote(deckID: deckID, front: front.text, back: back.text, tags: tagList, kind: kind)
            }
            onSave?(); dismiss(animated: true)
        } catch { showError(error) }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 2 : 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { [nil, "Front", "Back", "Tags"][section] }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return "Basic creates one card. Basic (and reversed) creates both directions. Cloze uses {{c1::hidden text}}. Changing note type may regenerate cards." }
        if section == 2 { return "Fields accept text and HTML." }
        return nil
    }
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { indexPath.section == 1 || indexPath.section == 2 ? 150 : 48 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        if indexPath.section == 0 {
            if indexPath.row == 0 {
                cell.textLabel?.text = "Deck"
                cell.detailTextLabel?.text = model.store.decks.first(where: { $0.id == deckID })?.name ?? "Select"
                cell.accessoryType = note == nil ? .disclosureIndicator : .none
                cell.selectionStyle = note == nil ? .default : .none
            } else {
                cell.textLabel?.text = "Type"
                cell.detailTextLabel?.text = Self.name(kind)
                cell.accessoryType = .disclosureIndicator
            }
        } else {
            let field: UIView = indexPath.section == 1 ? front : indexPath.section == 2 ? back : tags
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                field.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 4),
                field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -4)
            ])
            cell.selectionStyle = .none
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0 else { return }
        let sheet = UIAlertController(title: indexPath.row == 0 ? "Deck" : "Note Type", message: nil, preferredStyle: .actionSheet)
        if indexPath.row == 0 {
            guard note == nil else { return }
            for deck in model.store.decks {
                sheet.addAction(UIAlertAction(title: deck.name, style: .default) { [weak self] _ in self?.deckID = deck.id; self?.tableView.reloadData() })
            }
        } else {
            for type in [NoteKind.basic, .basicAndReversed, .cloze] {
                sheet.addAction(UIAlertAction(title: Self.name(type), style: .default) { [weak self] _ in self?.kind = type; self?.tableView.reloadData() })
            }
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = tableView
        sheet.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath)
        present(sheet, animated: true)
    }
    static func name(_ kind: NoteKind) -> String {
        switch kind { case .basic: return "Basic"; case .basicAndReversed: return "Basic (and reversed)"; case .cloze: return "Cloze" }
    }
}
