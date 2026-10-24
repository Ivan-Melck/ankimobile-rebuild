import UIKit
import UniformTypeIdentifiers
import FlashcardsCore

final class ToolsController: UITableViewController, UIDocumentPickerDelegate {
    private let model: AppModel
    private var restoring = false
    private var importDeckID: UUID?
    private let actions = ["Create Deck", "Import CSV / TSV", "Export CSV", "Export Collection Backup", "Restore Collection Backup", "Statistics"]
    init(model: AppModel) { self.model = model; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("Use init(model:)") }
    override func viewDidLoad() { super.viewDidLoad(); title = "Tools"; navigationController?.setToolbarHidden(true, animated: false) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { actions.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = actions[indexPath.row]; cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { "CSV columns: Front, Back, Tags (optional). Collection backups preserve scheduling and history. CSV exports contain note fields only." }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.row {
        case 0: createDeck()
        case 1: chooseImportDeck()
        case 2: export(backup: false)
        case 3: export(backup: true)
        case 4:
            restoring = true
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
            picker.delegate = self; present(picker, animated: true)
        default: navigationController?.pushViewController(StatisticsController(model: model), animated: true)
        }
    }
    private func createDeck() {
        let alert = UIAlertController(title: "Create Deck", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Deck name"; $0.accessibilityIdentifier = "newDeckName" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self else { return }
            do { _ = try self.model.store.createDeck(name: alert.textFields?.first?.text ?? "") } catch { self.showError(error) }
        })
        present(alert, animated: true)
    }
    private func chooseImportDeck() {
        let sheet = UIAlertController(title: "Import Into Deck", message: nil, preferredStyle: .actionSheet)
        for deck in model.store.decks {
            sheet.addAction(UIAlertAction(title: deck.name, style: .default) { [weak self] _ in
                guard let self else { return }
                self.importDeckID = deck.id; self.restoring = false
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText], asCopy: true)
                picker.delegate = self
                self.present(picker, animated: true)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = tableView.rectForRow(at: IndexPath(row: 1, section: 0))
        present(sheet, animated: true)
    }
    private func export(backup: Bool) {
        do {
            let name = backup ? "flashcards-backup-\(UUID().uuidString).json" : "flashcards-\(UUID().uuidString).csv"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            let data = backup ? try model.store.exportBackup() : Data(model.store.exportDelimitedText().utf8)
            try data.write(to: url, options: .atomic)
            shareFile(url)
        } catch { showError(error) }
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            if restoring {
                // Validate separately before showing a replacement confirmation.
                let validation = try CollectionStore(); try validation.restoreBackup(data)
                let alert = UIAlertController(title: "Replace Collection?", message: "This replaces all decks, notes, and review history. Export a backup first if you want to keep the current collection.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                alert.addAction(UIAlertAction(title: "Replace", style: .destructive) { [weak self] _ in
                    guard let self else { return }
                    do { try self.model.store.restoreBackup(data); self.navigationController?.popToRootViewController(animated: true) } catch { self.showError(error) }
                })
                present(alert, animated: true)
            } else {
                guard let text = String(data: data, encoding: .utf8), let deckID = importDeckID else { throw CollectionError.invalidInput("Choose a UTF-8 CSV or TSV file.") }
                let result = try model.store.importDelimitedText(text, deckID: deckID, delimiter: url.pathExtension.lowercased() == "tsv" ? "\t" : ",")
                showMessage("Import Complete", "Added \(result.importedNotes) notes and \(result.importedCards) cards. Skipped \(result.skippedDuplicates) duplicate fronts.")
            }
        } catch { showError(error) }
    }
}
