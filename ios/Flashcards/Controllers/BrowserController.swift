import UIKit
import FlashcardsCore

final class BrowserController: UITableViewController, UISearchResultsUpdating {
    private let model: AppModel
    private var results: [StudyCard] = []
    private let search = UISearchController(searchResultsController: nil)
    init(model: AppModel) { self.model = model; super.init(style: .plain) }
    required init?(coder: NSCoder) { fatalError("Use init(model:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Browse"
        tableView.accessibilityIdentifier = "cardBrowser"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "card")
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Search notes, deck:, tag:, is:"
        search.searchBar.accessibilityIdentifier = "browserSearch"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(add))
        definesPresentationContext = true
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
        reload()
    }
    private func reload() {
        results = model.store.search(search.searchBar.text ?? "")
        tableView.reloadData()
        let empty = UILabel()
        empty.text = "No cards found.\nTap + to add a note."
        empty.numberOfLines = 0; empty.textAlignment = .center; empty.textColor = .secondaryLabel
        tableView.backgroundView = results.isEmpty ? empty : nil
    }
    func updateSearchResults(for searchController: UISearchController) { reload() }
    @objc private func add() { openEditor(note: nil, deckID: model.store.decks.first?.id) }
    private func openEditor(note: Note?, deckID: UUID?) {
        let editor = EditorController(model: model, note: note, deckID: deckID)
        editor.onSave = { [weak self] in self?.reload() }
        present(UINavigationController(rootViewController: editor), animated: true)
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { results.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = results[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "card", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = item.note.front.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        content.secondaryText = item.deck.name + (item.card.suspended ? " · Suspended" : "")
        content.textProperties.numberOfLines = 2
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "card.\(item.card.id.uuidString)"
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let card = results[indexPath.row]
        openEditor(note: card.note, deckID: card.deck.id)
    }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let card = results[indexPath.row]
        let suspend = UIContextualAction(style: .normal, title: card.card.suspended ? "Unsuspend" : "Suspend") { [weak self] _, _, done in
            guard let self = self else { done(false); return }
            do { try self.model.store.setSuspended(cardID: card.card.id, suspended: !card.card.suspended); self.reload(); done(true) }
            catch { self.showError(error); done(false) }
        }
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            guard let self = self else { done(false); return }
            let alert = UIAlertController(title: "Delete Note?", message: "This removes the note and all cards generated from it.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(false) })
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
                do { try self.model.store.deleteNote(id: card.note.id); self.reload(); done(true) }
                catch { self.showError(error); done(false) }
            })
            self.present(alert, animated: true)
        }
        let configuration = UISwipeActionsConfiguration(actions: [delete, suspend])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
}
