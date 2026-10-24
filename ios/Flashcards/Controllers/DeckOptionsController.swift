import UIKit
import FlashcardsCore

final class DeckOptionsController: UITableViewController {
    private let model: AppModel
    private let deckID: UUID
    private var deck: Deck? { model.store.decks.first { $0.id == deckID } }
    init(model: AppModel, deck: Deck) { self.model = model; self.deckID = deck.id; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("Use init(model:deck:)") }
    override func viewDidLoad() { super.viewDidLoad(); title = "Deck Options"; navigationController?.setToolbarHidden(true, animated: false) }
    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 1 ? 2 : 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { [nil, "Daily Limits", nil][section] }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        if indexPath.section == 0 { cell.textLabel?.text = "Name"; cell.detailTextLabel?.text = deck?.name }
        else if indexPath.section == 1 {
            cell.textLabel?.text = indexPath.row == 0 ? "New Cards / Day" : "Reviews / Day"
            cell.detailTextLabel?.text = String(indexPath.row == 0 ? deck?.options.newCardsPerDay ?? 0 : deck?.options.reviewCardsPerDay ?? 0)
        } else {
            cell.textLabel?.text = "Delete Deck"; cell.textLabel?.textColor = .systemRed
            if deckID == model.store.defaultDeckID { cell.textLabel?.textColor = .tertiaryLabel; cell.selectionStyle = .none }
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 2 ? "Deleting a deck moves its cards to Default." : nil
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let deck else { return }
        if indexPath.section == 2 {
            guard deckID != model.store.defaultDeckID else { return }
            let alert = UIAlertController(title: "Delete \(deck.name)?", message: "Its cards will move to Default.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
                guard let self else { return }
                do { try self.model.store.deleteDeck(id: self.deckID); self.navigationController?.popToRootViewController(animated: true) } catch { self.showError(error) }
            })
            present(alert, animated: true); return
        }
        let name = indexPath.section == 0
        let alert = UIAlertController(title: name ? "Rename Deck" : "Daily Limit", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = name ? deck.name : String(indexPath.row == 0 ? deck.options.newCardsPerDay : deck.options.reviewCardsPerDay)
            field.keyboardType = name ? .default : .numberPad
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            do {
                let text = alert.textFields?.first?.text ?? ""
                if name { try self.model.store.renameDeck(id: self.deckID, name: text) }
                else {
                    guard let limit = Int(text), limit >= 0 else { throw CollectionError.invalidInput("Enter a nonnegative whole number.") }
                    var options = deck.options
                    if indexPath.row == 0 { options.newCardsPerDay = limit } else { options.reviewCardsPerDay = limit }
                    try self.model.store.updateDeckOptions(id: self.deckID, options: options)
                }
                self.tableView.reloadData()
            } catch { self.showError(error) }
        })
        present(alert, animated: true)
    }
}
