import UIKit

final class SettingsController: UITableViewController {
    private let model: AppModel
    init(model: AppModel) { self.model = model; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("Use init(model:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Preferences"
        navigationController?.setToolbarHidden(true, animated: false)
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 2 : 3 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 0 ? "Appearance" : "About" }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        if indexPath.section == 1 {
            if indexPath.row == 0 { cell.textLabel?.text = "Flashcards Rebuild"; cell.detailTextLabel?.text = "0.2"; cell.selectionStyle = .none }
            else { cell.textLabel?.text = indexPath.row == 1 ? "Source Code" : "Licenses & Credits"; cell.accessoryType = .disclosureIndicator }
        } else if indexPath.row == 0 {
            cell.textLabel?.text = "Theme"
            let choices = UISegmentedControl(items: ["System", "Light", "Dark"])
            choices.selectedSegmentIndex = model.appearance
            choices.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.model.appearance = choices.selectedSegmentIndex
                self.model.applyAppearance(to: self.view.window)
            }, for: .valueChanged)
            choices.accessibilityIdentifier = "appearance"
            cell.accessoryView = choices; cell.selectionStyle = .none
        } else {
            cell.textLabel?.text = "Card Text Size"; cell.detailTextLabel?.text = "\(Int(model.textSize)) pt"; cell.accessoryType = .disclosureIndicator
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 1 {
            if indexPath.row == 1, let url = URL(string: "https://github.com/Ivan-Melck/ankimobile-rebuild") { UIApplication.shared.open(url) }
            if indexPath.row == 2 { showMessage("Licenses & Credits", "GNU AGPL version 3 or later. Scheduling features are derived from JSchoreels/anki and Ankitects’ Anki. FSRS is provided by open-spaced-repetition under BSD-3-Clause. Full source, licenses, and model provenance are available through Source Code.") }
            return
        }
        guard indexPath.row == 1 else { return }
        let alert = UIAlertController(title: "Card Text Size", message: "Enter a size from 12 to 48 points.", preferredStyle: .alert)
        alert.addTextField { $0.keyboardType = .numberPad; $0.text = String(Int(self.model.textSize)) }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self, let size = Double(alert.textFields?.first?.text ?? ""), (12...48).contains(size) else { return }
            self.model.textSize = size; self.tableView.reloadData()
        })
        present(alert, animated: true)
    }
}
