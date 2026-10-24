import UIKit
import UniformTypeIdentifiers
import FlashcardsCore

final class AnkiDecksController: PlanningTableController, UIDocumentPickerDelegate {
    let state: AnkiAppState
    private var rows: [AnkiValue] = []
    init(state: AnkiAppState) { self.state = state; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Decks"; tableView.accessibilityIdentifier = "ankiDeckList"
        tableView.tableHeaderView = PlanningUI.hero(eyebrow: "Your collection, together", title: "Ready when you are", detail: "Bring your cards, templates, media and review history with you.", symbol: "rectangle.stack")
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(browse)); navigationItem.leftBarButtonItem?.accessibilityLabel = "Browse"
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(tools)); navigationItem.rightBarButtonItem?.accessibilityLabel = "Collection Tools"
        toolbarItems = [UIBarButtonItem(title: "Add", style: .plain, target: self, action: #selector(add)), .flexibleSpace(), UIBarButtonItem(title: "Synchronize", style: .plain, target: self, action: #selector(sync))]
        state.onProfileChanged = { [weak self] in self?.reload() }
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setToolbarHidden(false, animated: animated); reload() }
    private func reload() {
        do {
            let tree = try state.collection.deckTree(); rows = []
            func append(_ nodes: [AnkiValue]) { for node in nodes { rows.append(node); if !node["collapsed"].bool { append(node["children"].array) } } }
            append(tree["children"].array); tableView.reloadData()
        } catch { showError(error) }
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        let row = rows[p.row]
        let c = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        c.textLabel?.text = String(repeating: "  ", count: max(0, row["level"].int)) + row["name"].string
        c.textLabel?.font = .preferredFont(forTextStyle: .headline); c.textLabel?.numberOfLines = 0
        c.detailTextLabel?.text = "\(row["newCount"].int) new  ·  \(row["learnCount"].int) learning  ·  \(row["reviewCount"].int) review"
        c.detailTextLabel?.textColor = .secondaryLabel; c.accessoryType = .disclosureIndicator
        c.accessibilityIdentifier = "ankiDeck.\(row["deckId"].string)"; return c
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        tableView.deselectRow(at: p, animated: true)
        navigationController?.pushViewController(AnkiReviewerController(state: state, deckID: rows[p.row]["deckId"].string, name: rows[p.row]["name"].string), animated: true)
    }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt p: IndexPath) -> UISwipeActionsConfiguration? {
        let row = rows[p.row]
        let options = UIContextualAction(style: .normal, title: "Options") { [weak self] _, _, done in guard let self else { done(false); return }; self.navigationController?.pushViewController(AnkiOptionsController(state: self.state, deckID: row["deckId"].string), animated: true); done(true) }
        let collapse = UIContextualAction(style: .normal, title: row["collapsed"].bool ? "Expand" : "Collapse") { [weak self] _, _, done in
            guard let self else { done(false); return }; do { try self.state.collection.backend.call("Decks", "SetDeckCollapsed", ["deckId": row["deckId"], "collapsed": .bool(!row["collapsed"].bool), "scope": .number(0)]); self.reload(); done(true) } catch { self.showError(error); done(false) }
        }
        return UISwipeActionsConfiguration(actions: [options, collapse])
    }
    @objc private func add() { let editor = AnkiEditorController(state: state); editor.onSave = { [weak self] in self?.reload() }; presentAnkiEditor(editor) }
    @objc private func browse() { navigationController?.pushViewController(AnkiBrowserController(state: state), animated: true) }
    @objc private func sync() { navigationController?.pushViewController(AnkiSyncController(state: state), animated: true) }
    @objc private func tools() {
        let sheet = UIAlertController(title: "Collection", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Switch Collection", style: .default) { [weak self] _ in self?.chooseProfile() })
        sheet.addAction(UIAlertAction(title: "Import Anki Collection or Deck", style: .default) { [weak self] _ in
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true); picker.delegate = self; self?.present(picker, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Export Collection with Media", style: .default) { [weak self] _ in
            guard let self else { return }; let url = FileManager.default.temporaryDirectory.appendingPathComponent("Anki-\(UUID().uuidString).colpkg")
            self.ankiWork({ try self.state.collection.exportCollection(to: url); return url }) { self.shareFile($0) }
        })
        sheet.addAction(UIAlertAction(title: "Create Deck", style: .default) { [weak self] _ in
            self?.planningInput(title: "Create Deck") { name in
                guard let self else { return }; var deck = try self.state.collection.backend.call("Decks", "NewDeck"); deck["name"] = .string(name)
                try self.state.collection.backend.call("Decks", "AddDeck", deck.object); self.reload()
            }
        })
        sheet.addAction(UIAlertAction(title: "Check Collection", style: .default) { [weak self] _ in
            guard let self else { return }; self.ankiWork({ try self.state.collection.backend.call("Collection", "CheckDatabase")["problems"].array.map(\.string) }) { self.showMessage("Collection Check", $0.isEmpty ? "No problems found." : $0.joined(separator: "\n")) }
        })
        sheet.addAction(UIAlertAction(title: "Appearance", style: .default) { [weak self] _ in
            guard let self else { return }; self.navigationController?.pushViewController(PlanningChoiceController(title: "Appearance", values: [("System", ""), ("Light", ""), ("Dark", "")], selected: self.state.preferences.integer(forKey: "appearance")) { value in self.state.preferences.set(value, forKey: "appearance"); self.state.applyAppearance(self.view.window) }, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Source Code & Licenses", style: .default) { [weak self] _ in
            guard let self else { return }
            let controller = UIViewController(); controller.title = "Source & Licenses"
            let text = UITextView(); text.isEditable = false; text.font = .preferredFont(forTextStyle: .body); text.dataDetectorTypes = [.link]; text.backgroundColor = .systemBackground
            let licenses = Bundle.main.url(forResource: "reviewer-asset-licenses", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "See the repository for license texts."
            text.text = "Flashcards — independent native iOS rebuild\n\nEditable source and build instructions:\nhttps://github.com/Ivan-Melck/ankimobile-rebuild\n\nShared backend:\nhttps://github.com/JSchoreels/anki\n\n" + licenses
            text.textContainerInset = UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16); controller.view = text
            self.navigationController?.pushViewController(controller, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Original Local Collection", style: .default) { [weak self] _ in
            guard let self else { return }
            do { let appSupport = self.state.profilesURL.deletingLastPathComponent(); let model = AppModel(store: try CollectionStore(fileURL: appSupport.appendingPathComponent("collection.json"))); self.navigationController?.pushViewController(DecksController(model: model), animated: true) } catch { self.showError(error) }
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel)); sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem; present(sheet, animated: true)
    }
    private func chooseProfile() {
        do {
            let profiles = try FileManager.default.contentsOfDirectory(at: state.profilesURL, includingPropertiesForKeys: nil).filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("collection.anki2").path) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            let labels = profiles.map { url -> (String, String) in
                let name = state.preferences.string(forKey: "anki-profile-name-" + url.lastPathComponent) ?? (url.lastPathComponent == "default" ? "My Collection" : "Imported Collection")
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate).map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) } ?? ""
                return (name, date)
            }
            navigationController?.pushViewController(PlanningChoiceController(title: "Collections", values: labels, selected: profiles.firstIndex(of: state.collection.directory) ?? -1) { [weak self] i in
                guard let self, profiles[i] != self.state.collection.directory else { return }
                do { let collection = try AnkiCollection(directory: profiles[i]); self.state.useProfile(collection) } catch { self.showError(error) }
            }, animated: true)
        } catch { showError(error) }
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        guard ["apkg", "colpkg", "anki2", "anki21"].contains(url.pathExtension.lowercased()) else { showMessage("Choose an Anki File", "Import a .colpkg, .apkg or exported collection database."); return }
        let target = state.profilesURL.appendingPathComponent("import-\(UUID().uuidString)")
        ankiWork({
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try AnkiCollection.importFile(url, intoNewDirectory: target)
        }) { imported in
            self.state.preferences.set(url.deletingPathExtension().lastPathComponent, forKey: "anki-profile-name-" + imported.directory.lastPathComponent)
            let alert = UIAlertController(title: "Collection Imported", message: "Open this imported collection? Your current collection remains in its separate profile.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Keep Current", style: .cancel)); alert.addAction(UIAlertAction(title: "Open Collection", style: .default) { _ in self.state.useProfile(imported) }); self.present(alert, animated: true)
        }
    }
}
