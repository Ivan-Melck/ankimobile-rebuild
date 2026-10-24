import UIKit
import FlashcardsCore

final class PresetsController: UITableViewController {
    private let model: AppModel; private let deckID: UUID
    private var deck: Deck? { model.store.decks.first { $0.id == deckID } }
    init(model: AppModel, deckID: UUID) { self.model = model; self.deckID = deckID; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() { super.viewDidLoad(); title = "Scheduling Presets" }
    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 1 ? model.store.schedulingPresets.count : 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { [nil, "Shared presets", nil][section] }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { section == 2 ? "Save this deck’s current settings as a reusable preset. To update an existing preset, swipe it and choose Update. Linked decks receive that change." : nil }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        if p.section == 2 { let c = PlanningUI.cell("Save current settings as preset", symbol: "plus.circle"); c.textLabel?.textColor = PlanningUI.accent; return c }
        let preset = p.section == 1 ? model.store.schedulingPresets[p.row] : nil
        let c = PlanningUI.cell(preset?.name ?? "Local to this deck", value: preset?.options.engine.title)
        if preset?.id == deck?.options.presetID { c.accessoryType = .checkmark }; return c
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        tableView.deselectRow(at: p, animated: true); guard var options = deck?.options else { return }
        if p.section == 2 {
            planningInput(title: "New Preset", message: "Give these settings a name, such as Languages or Exam prep.") { [weak self] name in
                guard let self else { return }; let preset = SchedulingPreset(name: name, options: self.model.store.schedulingOptions(deckID: self.deckID))
                try self.model.store.savePreset(preset); options.presetID = preset.id
                try self.model.store.updateDeckOptions(id: self.deckID, options: options); self.tableView.reloadData()
            }; return
        }
        if p.section == 0 { options.scheduling = model.store.schedulingOptions(deckID: deckID); options.presetID = nil }
        else { options.presetID = model.store.schedulingPresets[p.row].id }
        do { try model.store.updateDeckOptions(id: deckID, options: options); navigationController?.popViewController(animated: true) } catch { showError(error) }
    }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt p: IndexPath) -> UISwipeActionsConfiguration? {
        guard p.section == 1 else { return nil }
        var preset = model.store.schedulingPresets[p.row]
        let update = UIContextualAction(style: .normal, title: "Update") { [weak self] _, _, done in
            guard let self else { done(false); return }
            preset.options = self.model.store.schedulingOptions(deckID: self.deckID)
            do { try self.model.store.savePreset(preset); self.tableView.reloadData(); done(true) } catch { done(false); self.showError(error) }
        }; update.backgroundColor = PlanningUI.accent
        return UISwipeActionsConfiguration(actions: [update])
    }
}

final class SchedulingRulesController: PlanningTableController {
    private let model: AppModel; private let deckID: UUID
    private var rules: [SchedulingRule] { model.store.decks.first { $0.id == deckID }?.options.rules ?? [] }
    init(model: AppModel, deckID: UUID) { self.model = model; self.deckID = deckID; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Card Rules"; tableView.rowHeight = UITableView.automaticDimension
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(add))
        navigationItem.leftBarButtonItem = editButtonItem
        tableView.tableHeaderView = PlanningUI.hero(eyebrow: "Adapt to the card", title: "A target for what matters", detail: "Rules run from top to bottom. The first match sets that card’s preset and retention.", symbol: "line.3.horizontal.decrease.circle")
    }
    override func setEditing(_ editing: Bool, animated: Bool) { super.setEditing(editing, animated: animated); tableView.setEditing(editing, animated: animated) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { max(1, rules.count) }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        let c = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        guard !rules.isEmpty else { c.textLabel?.text = "Every card has its own context"; c.detailTextLabel?.text = "Add a rule, such as tag:exam → 95% retention."; c.detailTextLabel?.numberOfLines = 0; c.selectionStyle = .none; return c }
        let r = rules[p.row]; let preset = model.store.schedulingPresets.first { $0.id == r.presetID }
        c.textLabel?.text = r.query; c.detailTextLabel?.text = "\(Int((r.retention * 100).rounded()))% retention · \(preset?.name ?? "Deck model")"
        c.detailTextLabel?.textColor = .secondaryLabel; c.accessoryType = .disclosureIndicator; return c
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { "Examples: tag:exam, prop:lapses>=3, is:new. Combine terms with spaces. Swipe to delete; use Edit to reorder." }
    override func tableView(_ tableView: UITableView, canEditRowAt p: IndexPath) -> Bool { !rules.isEmpty }
    override func tableView(_ tableView: UITableView, canMoveRowAt p: IndexPath) -> Bool { !rules.isEmpty }
    override func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) { var items = rules; items.insert(items.remove(at: source.row), at: destination.row); persist(items) }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt p: IndexPath) { var items = rules; items.remove(at: p.row); persist(items) }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) { tableView.deselectRow(at: p, animated: true); if !rules.isEmpty { edit(rules[p.row]) } }
    @objc private func add() { edit(nil) }
    private func persist(_ rules: [SchedulingRule]) {
        guard var options = model.store.decks.first(where: { $0.id == deckID })?.options else { return }; options.rules = rules
        do { try model.store.updateDeckOptions(id: deckID, options: options); tableView.reloadData() } catch { showError(error) }
    }
    private func edit(_ existing: SchedulingRule?) {
        let alert = UIAlertController(title: existing == nil ? "Add Card Rule" : "Edit Card Rule", message: "Enter a card search and a retention target from 70 to 99%.", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "tag:exam"; $0.text = existing?.query; $0.accessibilityIdentifier = "ruleQuery"; $0.autocapitalizationType = .none }
        alert.addTextField { $0.placeholder = "95"; $0.keyboardType = .numberPad; $0.text = existing.map { String(Int(($0.retention * 100).rounded())) }; $0.accessibilityIdentifier = "ruleRetention" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Next", style: .default) { [weak self] _ in
            guard let self else { return }
            let query = (alert.textFields?[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty, let percent = Double(alert.textFields?[1].text ?? ""), (70...99).contains(percent) else { self.showMessage("Check your rule", "Enter a search and a percentage from 70 to 99."); return }
            let presets = self.model.store.schedulingPresets
            self.navigationController?.pushViewController(PlanningChoiceController(title: "Rule Preset", values: [("Use deck model", "Change only the retention target")] + presets.map { ($0.name, $0.options.engine.title) }, selected: existing?.presetID.flatMap { id in presets.firstIndex { $0.id == id }.map { $0 + 1 } } ?? 0) { [weak self] index in
                guard let self else { return }; var items = self.rules
                let r = SchedulingRule(id: existing?.id ?? UUID(), query: query, retention: percent / 100, presetID: index == 0 ? nil : presets[index - 1].id)
                if let i = items.firstIndex(where: { $0.id == r.id }) { items[i] = r } else { items.append(r) }; self.persist(items)
            }, animated: true)
        }); present(alert, animated: true)
    }
}
