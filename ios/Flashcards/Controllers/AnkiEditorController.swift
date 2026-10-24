import UIKit
import FlashcardsCore

final class AnkiEditorController: UITableViewController {
    let state: AnkiAppState
    var onSave: (() -> Void)?
    private var note: AnkiValue?
    private var deckID: String
    private var typeID: String = ""
    private var fields: [String] = [], fieldNames: [String] = []
    private var tags = ""
    init(state: AnkiAppState, note: AnkiValue? = nil, deckID: String = "1") { self.state = state; self.note = note; self.deckID = deckID; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); title = note == nil ? "Add Note" : "Edit Note"; tableView.rowHeight = UITableView.automaticDimension
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save)); navigationItem.rightBarButtonItem?.accessibilityIdentifier = "ankiSaveNote"
        do {
            typeID = try note?["notetypeId"].string ?? state.collection.notetypes().first?["id"].string ?? ""
            try loadType(reload: false); if let note { fields = note["fields"].array.map(\.string); tags = note["tags"].array.map(\.string).joined(separator: " ") }; tableView.reloadData()
        } catch { showError(error) }
    }
    private func loadType(reload: Bool = true) throws {
        let previous = fields, byName = Dictionary(uniqueKeysWithValues: zip(fieldNames, fields))
        let type = try state.collection.notetype(typeID); fieldNames = type["fields"].array.map { $0["name"].string }
        fields = fieldNames.enumerated().map { index, name in byName[name] ?? (previous.indices.contains(index) ? previous[index] : "") }
        if reload { tableView.reloadData() }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 1 ? fields.count : section == 0 ? 2 : 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { [nil, "Fields", "Tags"][section] }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        if p.section == 0 {
            if p.row == 0 { return PlanningUI.cell("Note Type", value: (try? state.collection.notetypes().first { $0["id"].string == typeID }?["name"].string) ?? "", disclosure: note == nil) }
            return PlanningUI.cell("Deck", value: (try? state.collection.decks().first { $0["id"].string == deckID }?["name"].string) ?? "", disclosure: note == nil)
        }
        let index = p.row
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let editor = UITextView(); editor.font = .preferredFont(forTextStyle: .body); editor.isScrollEnabled = false
        editor.isEditable = true; editor.isSelectable = true
        editor.smartQuotesType = .no; editor.smartDashesType = .no; editor.autocorrectionType = .no; editor.autocapitalizationType = .none; editor.spellCheckingType = .no
        editor.text = p.section == 1 ? fields[index] : tags; editor.accessibilityLabel = p.section == 1 ? fieldNames[index] : "Tags"
        editor.accessibilityIdentifier = p.section == 1 ? "ankiField.\(index)" : "ankiTags"
        let label = UILabel(); label.font = .preferredFont(forTextStyle: .caption1); label.textColor = .secondaryLabel; label.text = p.section == 1 ? fieldNames[index] : "Separate tags with spaces"
        let stack = UIStackView(arrangedSubviews: [label, editor]); stack.axis = .vertical; stack.spacing = 6; stack.translatesAutoresizingMaskIntoConstraints = false; cell.contentView.addSubview(stack)
        editor.heightAnchor.constraint(greaterThanOrEqualToConstant: p.section == 1 ? 110 : 44).isActive = true
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor), stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12), stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12)])
        // Each text view writes to the backing model before cells can be reused.
        NotificationCenter.default.addObserver(self, selector: #selector(textChanged(_:)), name: UITextView.textDidChangeNotification, object: editor)
        editor.tag = p.section == 1 ? index : -1
        return cell
    }
    @objc private func textChanged(_ notification: Notification) { guard let view = notification.object as? UITextView else { return }; if view.tag == -1 { tags = view.text } else if fields.indices.contains(view.tag) { fields[view.tag] = view.text } }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        tableView.deselectRow(at: p, animated: true)
        if p.section > 0 {
            let stack = tableView.cellForRow(at: p)?.contentView.subviews.first as? UIStackView
            (stack?.arrangedSubviews.last as? UITextView)?.becomeFirstResponder(); return
        }
        guard note == nil else { return }
        do {
            let values = p.row == 0 ? try state.collection.notetypes() : try state.collection.decks()
            navigationController?.pushViewController(PlanningChoiceController(title: p.row == 0 ? "Note Type" : "Deck", values: values.map { ($0["name"].string, "") }, selected: values.firstIndex { $0["id"].string == (p.row == 0 ? typeID : deckID) } ?? 0) { [weak self] i in
                guard let self else { return }; if p.row == 0 { self.typeID = values[i]["id"].string; do { try self.loadType() } catch { self.showError(error) } } else { self.deckID = values[i]["id"].string }; self.tableView.reloadData()
            }, animated: true)
        } catch { showError(error) }
    }
    @objc private func cancel() { dismiss(animated: true) }
    @objc private func save() {
        view.endEditing(true)
        do {
            if var note { note["fields"] = .array(fields.map(AnkiValue.string)); note["tags"] = .array(tags.split(whereSeparator: \.isWhitespace).map { .string(String($0)) }); try state.collection.updateNote(note) }
            else { _ = try state.collection.addNote(notetypeID: typeID, deckID: deckID, fields: fields, tags: tags.split(whereSeparator: \.isWhitespace).map(String.init)) }
            dismiss(animated: true, completion: onSave)
        } catch { showError(error) }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}

final class AnkiBrowserController: UITableViewController, UISearchResultsUpdating {
    let state: AnkiAppState
    private var ids: [String] = []
    private let search = UISearchController(searchResultsController: nil)
    init(state: AnkiAppState) { self.state = state; super.init(style: .plain) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Browse"; tableView.accessibilityIdentifier = "ankiBrowser"
        search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false; search.searchBar.placeholder = "Search your Anki collection"; navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false; navigationItem.rightBarButtonItem = editButtonItem
        tableView.allowsMultipleSelectionDuringEditing = true; definesPresentationContext = true
        toolbarItems = [UIBarButtonItem(title: "Suspend", style: .plain, target: self, action: #selector(suspendSelected)), .flexibleSpace(), UIBarButtonItem(title: "Move", style: .plain, target: self, action: #selector(moveSelected))]
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setToolbarHidden(!isEditing, animated: animated); reload() }
    override func setEditing(_ editing: Bool, animated: Bool) { super.setEditing(editing, animated: animated); navigationController?.setToolbarHidden(!editing, animated: animated) }
    private func reload() { do { ids = try state.collection.search(search.searchBar.text ?? ""); tableView.reloadData() } catch { showError(error) } }
    func updateSearchResults(for searchController: UISearchController) { reload() }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { ids.count }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        do { let card = try state.collection.getCard(ids[p.row]); let note = try state.collection.getNote(card["noteId"].string)
            cell.textLabel?.text = CardRenderer.plainText(note["fields"].array.first?.string ?? ""); cell.textLabel?.numberOfLines = 2
            cell.detailTextLabel?.text = "\(card["reps"].int) reviews · \(card["lapses"].int) lapses" + (card["queue"].int == -1 ? " · Suspended" : "")
        } catch { cell.textLabel?.text = error.localizedDescription }
        cell.accessoryType = .disclosureIndicator; return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        guard !isEditing else { return }; tableView.deselectRow(at: p, animated: true)
        do { let card = try state.collection.getCard(ids[p.row]); let note = try state.collection.getNote(card["noteId"].string); let editor = AnkiEditorController(state: state, note: note, deckID: card["deckId"].string); editor.onSave = { [weak self] in self?.reload() }; presentAnkiEditor(editor) } catch { showError(error) }
    }
    private var selected: [AnkiValue] { (tableView.indexPathsForSelectedRows ?? []).map { .string(ids[$0.row]) } }
    @objc private func suspendSelected() { do { try state.collection.backend.call("Scheduler", "BuryOrSuspendCards", ["cardIds": .array(selected), "mode": .number(0)]); reload() } catch { showError(error) } }
    @objc private func moveSelected() {
        do { let decks = try state.collection.decks(), cards = selected
            navigationController?.pushViewController(PlanningChoiceController(title: "Move Cards", values: decks.map { ($0["name"].string, "") }, selected: -1) { [weak self] i in
                guard let self else { return }; do { try self.state.collection.backend.call("Cards", "SetDeck", ["cardIds": .array(cards), "deckId": decks[i]["id"]]); self.reload() } catch { self.showError(error) }
            }, animated: true)
        } catch { showError(error) }
    }
}

extension UIViewController {
    func presentAnkiEditor(_ editor: AnkiEditorController) {
        let navigation = UINavigationController(rootViewController: editor)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }
}
