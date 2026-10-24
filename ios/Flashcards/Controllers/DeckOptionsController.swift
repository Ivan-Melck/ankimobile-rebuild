import UIKit
import FlashcardsCore

final class DeckOptionsController: UITableViewController {
    private let model: AppModel
    private let deckID: UUID
    private var deck: Deck? { model.store.decks.first { $0.id == deckID } }
    private var settings: SchedulingOptions { model.store.schedulingOptions(deckID: deckID) }
    private enum Group: Int, CaseIterable { case identity, scheduling, limits, learning, ordering, neural, analysis, rules, delete }
    init(model: AppModel, deck: Deck) { self.model = model; self.deckID = deck.id; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Deck Options"; tableView.accessibilityIdentifier = "deckOptions"
        tableView.rowHeight = UITableView.automaticDimension; tableView.estimatedRowHeight = 52
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setToolbarHidden(true, animated: animated); reload() }
    private func reload() {
        tableView.tableHeaderView = PlanningUI.hero(eyebrow: deck?.name ?? "Deck", title: settings.engine.title,
            detail: settings.engine == .legacy ? "Choose a memory model to unlock retention planning." : "\(Int((settings.desiredRetention * 100).rounded()))% desired retention · tuned to your pace", symbol: "brain")
        tableView.reloadData()
    }
    private func update(_ change: (inout SchedulingOptions) -> Void) {
        guard var options = deck?.options else { return }; var value = settings; change(&value)
        options.scheduling = value; options.presetID = nil
        do { try model.store.updateDeckOptions(id: deckID, options: options); reload() } catch { showError(error) }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { Group.allCases.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let group = Group(rawValue: section)!
        if settings.engine == .legacy && [.learning, .ordering, .analysis, .rules].contains(group) { return 0 }
        if settings.engine == .legacy && group == .scheduling { return 1 }
        switch group {
        case .identity: return 2; case .scheduling: return 3; case .limits: return 2; case .learning: return 4
        case .ordering: return 4; case .neural: return settings.engine.isRWKV ? 3 : 0; case .analysis: return 2
        case .rules: return 1; case .delete: return 1
        }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard self.tableView(tableView, numberOfRowsInSection: section) > 0 else { return nil }
        return ["Deck & preset", "Memory & retention", "Daily limits", "Learning", "Order & repeat spacing", settings.engine.isRWKV ? "RWKV advanced" : nil, "Understand your model", "Conditional scheduling", nil][section]
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard self.tableView(tableView, numberOfRowsInSection: section) > 0 else { return nil }
        switch Group(rawValue: section)! {
        case .identity: return "Presets share settings across decks. Editing a setting creates a local override; saving a preset updates its linked decks."
        case .scheduling: return settings.engine.detail + " Changing models uses your recorded history; it does not rewrite existing due dates."
        case .learning: return "Same-day intervals can be as short as one second. Skipping a learning or relearning queue gives those answers an interval of at least one day."
        case .ordering: return "A repeated card must satisfy both spacing limits. Zero disables a limit."
        case .neural: return settings.engine.isRWKV ? "SM56 is the current small model. Compact state reduces memory; F32 favors precision. Grade order keeps Again ≤ Hard ≤ Good ≤ Easy." : nil
        case .rules: return "The first matching rule wins. Use tags, card properties, or a saved preset to adapt scheduling to particular cards."
        case .delete: return "Deleting a deck moves its cards to Default."
        default: return nil
        }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        let s = settings
        switch Group(rawValue: p.section)! {
        case .identity:
            if p.row == 0 { return PlanningUI.cell("Name", value: deck?.name, disclosure: true) }
            let preset = model.store.schedulingPresets.first { $0.id == deck?.options.presetID }
            return PlanningUI.cell("Scheduling preset", value: preset?.name ?? "This deck", symbol: "square.stack", disclosure: true)
        case .scheduling:
            if p.row == 0 { let cell = PlanningUI.cell("Memory model", value: s.engine.title, symbol: "brain", disclosure: true); cell.accessibilityIdentifier = "memoryModel"; return cell }
            if p.row == 1 { let cell = PlanningUI.cell("Desired retention", value: "\(Int((s.desiredRetention * 100).rounded()))%", symbol: "scope", disclosure: true); cell.accessibilityIdentifier = "desiredRetention"; return cell }
            let cell = PlanningUI.cell("Help me decide", symbol: "sparkles", disclosure: true); cell.textLabel?.textColor = PlanningUI.accent; return cell
        case .limits: return PlanningUI.cell(p.row == 0 ? "New Cards / Day" : "Reviews / Day", value: String(p.row == 0 ? deck?.options.newCardsPerDay ?? 0 : deck?.options.reviewCardsPerDay ?? 0), disclosure: true)
        case .learning:
            switch p.row {
            case 0: return PlanningUI.toggle("Allow same-day reviews", value: s.allowSameDay, id: "allowSameDay") { [weak self] value in self?.update { $0.allowSameDay = value } }
            case 1: return PlanningUI.toggle("Skip learning steps", value: s.skipLearning, id: "skipLearning") { [weak self] value in self?.update { $0.skipLearning = value } }
            case 2: return PlanningUI.toggle("Skip relearning steps", value: s.skipRelearning, id: "skipRelearning") { [weak self] value in self?.update { $0.skipRelearning = value } }
            default: return PlanningUI.cell("Learning cards", value: s.learningOrder.title, disclosure: true)
            }
        case .ordering:
            switch p.row {
            case 0: return PlanningUI.cell("Review order", value: s.reviewOrder.title, disclosure: true)
            case 1: return PlanningUI.cell("Minimum other reviews", value: String(s.minimumOtherReviews), disclosure: true)
            case 2: return PlanningUI.cell("Minimum elapsed time", value: "\(s.minimumSeconds) sec", disclosure: true)
            default: return PlanningUI.cell("Maximum interval", value: "\(s.maximumInterval) days", disclosure: true)
            }
        case .neural:
            if p.row == 0 { return PlanningUI.cell("Model weights", value: s.rwkvModel.uppercased(), disclosure: true) }
            if p.row == 1 { return PlanningUI.cell("State precision", value: s.precision == "cards_int4_notes_int8" ? "Compact · mixed" : s.precision.uppercased(), disclosure: true) }
            return PlanningUI.toggle("Keep grade order", value: s.enforceGradeOrder, id: "gradeOrder") { [weak self] value in self?.update { $0.enforceGradeOrder = value } }
        case .analysis:
            return p.row == 0 ? PlanningUI.cell("Calibration & optimization", symbol: "chart.xyaxis.line", disclosure: true) : PlanningUI.toggle("Analyze same-day reviews", value: s.includeSameDayInAnalysis, id: "analyzeSameDay") { [weak self] value in self?.update { $0.includeSameDayInAnalysis = value } }
        case .rules: return PlanningUI.cell("Card rules", value: "\(deck?.options.rules?.count ?? 0)", symbol: "line.3.horizontal.decrease.circle", disclosure: true)
        case .delete:
            let cell = PlanningUI.cell("Delete Deck"); cell.textLabel?.textColor = deckID == model.store.defaultDeckID ? .tertiaryLabel : .systemRed; return cell
        }
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        tableView.deselectRow(at: p, animated: true); guard let deck else { return }
        switch Group(rawValue: p.section)! {
        case .identity:
            if p.row == 0 { planningInput(title: "Rename Deck", value: deck.name) { [weak self] name in guard let self else { return }; try self.model.store.renameDeck(id: self.deckID, name: name); self.reload() } }
            else { navigationController?.pushViewController(PresetsController(model: model, deckID: deckID), animated: true) }
        case .scheduling:
            if p.row == 0 {
                let engines = SchedulingEngine.allCases
                choose("Memory Model", values: engines.map { ($0.title, $0.detail) }, selected: engines.firstIndex(of: settings.engine) ?? 0) { [weak self] i in self?.update { $0.engine = engines[i]; $0.parameters = [] } }
            } else if p.row == 1 {
                navigationController?.pushViewController(RetentionController(value: settings.desiredRetention) { [weak self] value in self?.update { $0.desiredRetention = value } }, animated: true)
            } else { navigationController?.pushViewController(StudyPlanController(model: model, deckID: deckID), animated: true) }
        case .limits:
            integer(p.row == 0 ? "New cards per day" : "Reviews per day", value: p.row == 0 ? deck.options.newCardsPerDay : deck.options.reviewCardsPerDay) { [weak self] n in
                guard let self else { return }; var options = deck.options
                if p.row == 0 { options.newCardsPerDay = n } else { options.reviewCardsPerDay = n }
                do { try self.model.store.updateDeckOptions(id: self.deckID, options: options); self.reload() } catch { self.showError(error) }
            }
        case .learning:
            if p.row == 3 { let orders = LearningOrder.allCases; choose("Learning Order", values: orders.map { ($0.title, "") }, selected: orders.firstIndex(of: settings.learningOrder) ?? 0) { [weak self] i in self?.update { $0.learningOrder = orders[i] } } }
        case .ordering:
            switch p.row {
            case 0: let orders = ReviewOrder.allCases; choose("Review Order", values: orders.map { ($0.title, "") }, selected: orders.firstIndex(of: settings.reviewOrder) ?? 0) { [weak self] i in self?.update { $0.reviewOrder = orders[i] } }
            case 1: integer("Minimum other reviews", value: settings.minimumOtherReviews) { [weak self] n in self?.update { $0.minimumOtherReviews = n } }
            case 2: integer("Minimum seconds", value: settings.minimumSeconds) { [weak self] n in self?.update { $0.minimumSeconds = n } }
            default: integer("Maximum interval in days", value: settings.maximumInterval) { [weak self] n in self?.update { $0.maximumInterval = n } }
            }
        case .neural:
            if p.row == 0 { let keys = ["sm56", "sm55", "sm40", "sm36", "legacy"]; choose("RWKV Model", values: [("SM56", "Current small model · recommended"), ("SM55", "Previous small model"), ("SM40", "SM40v2 weights"), ("SM36", "Earlier small model"), ("Legacy", "Original model · uses more memory")], selected: keys.firstIndex(of: settings.rwkvModel) ?? 0) { [weak self] i in self?.update { $0.rwkvModel = keys[i] } } }
            else if p.row == 1 { let keys = ["cards_int4_notes_int8", "f32", "int8", "int4"]; choose("State Precision", values: [("Compact · mixed", "INT4 cards, INT8 notes · recommended"), ("F32", "Full precision"), ("INT8", "Compact 8-bit state"), ("INT4", "Smallest 4-bit state")], selected: keys.firstIndex(of: settings.precision) ?? 0) { [weak self] i in self?.update { $0.precision = keys[i] } } }
        case .analysis: if p.row == 0 { navigationController?.pushViewController(CalibrationController(model: model, deckID: deckID), animated: true) }
        case .rules: navigationController?.pushViewController(SchedulingRulesController(model: model, deckID: deckID), animated: true)
        case .delete:
            guard deckID != model.store.defaultDeckID else { return }
            let alert = UIAlertController(title: "Delete \(deck.name)?", message: "Its cards will move to Default.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel)); alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
                guard let self else { return }; do { try self.model.store.deleteDeck(id: self.deckID); self.navigationController?.popToRootViewController(animated: true) } catch { self.showError(error) }
            }); present(alert, animated: true)
        }
    }
    private func integer(_ title: String, value: Int, save: @escaping (Int) -> Void) {
        planningInput(title: title, value: String(value), numeric: true) { text in
            guard let n = Int(text), (0...100000).contains(n) else { throw CollectionError.invalidInput("Enter a whole number between 0 and 100000.") }; save(n)
        }
    }
    private func choose(_ title: String, values: [(String, String)], selected: Int, choice: @escaping (Int) -> Void) { navigationController?.pushViewController(PlanningChoiceController(title: title, values: values, selected: selected, choose: choice), animated: true) }
}

final class RetentionController: UIViewController {
    private var value: Double
    private let save: (Double) -> Void
    private let percent = UILabel()
    init(value: Double, save: @escaping (Double) -> Void) { self.value = value; self.save = save; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Desired Retention"; view.backgroundColor = .systemGroupedBackground
        let hero = PlanningUI.hero(eyebrow: "Your memory target", title: "Remember more.\nSpend a little more time.", detail: "Choose the chance of recalling a card when it comes up for review.", symbol: "scope")
        hero.heightAnchor.constraint(equalToConstant: 205).isActive = true
        percent.font = .systemFont(ofSize: 64, weight: .semibold); percent.textAlignment = .center; percent.textColor = PlanningUI.accent
        let slider = UISlider(); slider.minimumValue = 70; slider.maximumValue = 99; slider.value = Float(value * 100); slider.tintColor = PlanningUI.accent; slider.accessibilityIdentifier = "retentionSlider"
        slider.addAction(UIAction { [weak self] _ in self?.value = Double(slider.value.rounded()) / 100; self?.refresh() }, for: .valueChanged)
        let note = UILabel(); note.text = "70% · lighter workload                         99% · more reviews"; note.font = .preferredFont(forTextStyle: .caption1); note.textColor = .secondaryLabel; note.numberOfLines = 0
        let button = Theme.button("Use this target", identifier: "saveRetention", action: UIAction { [weak self] _ in guard let self else { return }; self.save(self.value); self.navigationController?.popViewController(animated: true) })
        button.backgroundColor = PlanningUI.accent; button.tintColor = .white; button.layer.cornerRadius = 14
        let stack = UIStackView(arrangedSubviews: [hero, percent, slider, note, button]); stack.axis = .vertical; stack.spacing = 24; stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)])
        refresh()
    }
    private func refresh() { percent.text = "\(Int((value * 100).rounded()))%" }
}
