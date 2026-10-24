import UIKit
import FlashcardsCore

final class StudyPlanController: UITableViewController {
    private let model: AppModel
    private var deckID: UUID
    private var days = 30
    private var forecast: WorkloadForecast?
    private var busy = false
    private var failure: String?
    private var generation = 0
    private var options: SchedulingOptions { model.store.schedulingOptions(deckID: deckID) }
    private var deck: Deck { model.store.decks.first { $0.id == deckID } ?? model.store.decks[0] }
    init(model: AppModel, deckID: UUID? = nil) { self.model = model; self.deckID = deckID ?? model.store.defaultDeckID; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Study Plan"; tableView.accessibilityIdentifier = "studyPlan"
        tableView.rowHeight = UITableView.automaticDimension; tableView.estimatedRowHeight = 70
        tableView.tableHeaderView = PlanningUI.hero(eyebrow: "A little more intentional", title: "Find your study rhythm", detail: "Balance what you remember with the time you spend reviewing.", symbol: "sparkles")
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated); navigationController?.setToolbarHidden(true, animated: animated)
        // Forecasts are snapshots. Returning from options always invalidates an older result.
        generation += 1; busy = false; forecast = nil; failure = nil; tableView.reloadData()
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section { case 0: return 3; case 1: return 2; case 2: return max(1, forecast?.points.count ?? 0); default: return 2 }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { ["Your plan", "Compare retention targets", "Estimated workload", "Make it yours"][section] }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0: return "Changes affect future answers. Existing due dates stay in place."
        case 1: return "Uses the selected engine, this deck’s cards and daily limits. Compare a uniform target before applying it."
        case 2: return "Seeded estimates, not a guarantee. Review time and outcomes vary. Suspended and buried cards are excluded; conditional rules and repeat spacing are not simulated."
        case 3: return "Keep everyday choices here. Model details and repeat spacing live in Deck Options."
        default: return nil
        }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        if p.section == 0 {
            if p.row == 0 { return PlanningUI.cell("Deck", value: deck.name, symbol: "rectangle.stack", disclosure: true) }
            if p.row == 1 { return PlanningUI.cell("Memory model", value: options.engine.title, symbol: "brain", disclosure: true) }
            return PlanningUI.cell("Desired retention", value: "\(Int((options.desiredRetention * 100).rounded()))%", symbol: "scope", disclosure: true)
        }
        if p.section == 1 {
            if p.row == 0 {
                let cell = PlanningUI.cell("Look ahead")
                let control = UISegmentedControl(items: ["30 days", "90", "365"]); control.selectedSegmentIndex = [30,90,365].firstIndex(of: days) ?? 0
                control.accessibilityIdentifier = "forecastHorizon"
                control.addAction(UIAction { [weak self] _ in
                    guard let self else { return }; self.days = [30,90,365][control.selectedSegmentIndex]
                    self.generation += 1; self.busy = false; self.forecast = nil; self.failure = nil; self.tableView.reloadData()
                }, for: .valueChanged)
                cell.accessoryView = control; return cell
            }
            let cell = PlanningUI.cell(busy ? "Calculating your plan…" : "Compare targets", symbol: "slider.horizontal.3")
            cell.textLabel?.textColor = PlanningUI.accent; cell.accessibilityIdentifier = "compareTargets"
            if busy { let spinner = UIActivityIndicatorView(style: .medium); spinner.startAnimating(); cell.accessoryView = spinner }
            return cell
        }
        if p.section == 2 {
            guard let point = forecast?.points[p.row] else {
                let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
                cell.textLabel?.text = failure == nil ? "Your next decision, made clearer" : "Couldn’t calculate this plan"
                cell.detailTextLabel?.text = failure ?? "Compare 80%, 85%, 90% and 95% retention to see their cost."
                cell.detailTextLabel?.numberOfLines = 0; cell.detailTextLabel?.textColor = .secondaryLabel
                cell.selectionStyle = .none; return cell
            }
            let cell = ForecastCell()
            cell.configure(point, days: days, maxSeconds: forecast!.points.map(\.seconds).max() ?? 1, selected: abs(point.retention - options.desiredRetention) < 0.005)
            return cell
        }
        return p.row == 0 ? PlanningUI.cell("Deck Options", symbol: "switch.2", disclosure: true) : PlanningUI.cell("Calibration & optimization", symbol: "chart.xyaxis.line", disclosure: true)
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        tableView.deselectRow(at: p, animated: true)
        if p.section == 0 && p.row == 0 {
            let decks = model.store.decks
            navigationController?.pushViewController(PlanningChoiceController(title: "Choose Deck", values: decks.map { deck in (deck.name, "\(model.store.cards.filter { $0.deckID == deck.id }.count) cards") }, selected: decks.firstIndex { $0.id == deckID } ?? 0) { [weak self] i in self?.deckID = decks[i].id }, animated: true)
        } else if p.section == 0 || (p.section == 3 && p.row == 0) {
            navigationController?.pushViewController(DeckOptionsController(model: model, deck: deck), animated: true)
        } else if p.section == 1 && p.row == 1 { compare() }
        else if p.section == 2, let point = forecast?.points[p.row] {
            let alert = UIAlertController(title: "Use \(Int((point.retention * 100).rounded()))% retention?", message: "This becomes the deck’s local target for future answers. Conditional card rules still take priority.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Apply Target", style: .default) { [weak self] _ in
                guard let self else { return }
                do { var deckOptions = self.deck.options; var settings = self.options; settings.desiredRetention = point.retention
                    deckOptions.scheduling = settings; deckOptions.presetID = nil
                    try self.model.store.updateDeckOptions(id: self.deckID, options: deckOptions); self.tableView.reloadData()
                } catch { self.showError(error) }
            }); present(alert, animated: true)
        } else if p.section == 3 { navigationController?.pushViewController(CalibrationController(model: model, deckID: deckID), animated: true) }
    }
    private func compare() {
        guard !busy else { return }; busy = true; failure = nil; forecast = nil; generation += 1
        let token = generation, id = deckID, horizon = days
        tableView.reloadData()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }; let result = Result { try self.model.store.forecast(deckID: id, days: horizon) }
            DispatchQueue.main.async {
                guard self.generation == token else { return }; self.busy = false
                switch result { case .success(let result): self.forecast = result; case .failure(let error): self.failure = error.localizedDescription }
                self.tableView.reloadData()
            }
        }
    }
}

private final class ForecastCell: UITableViewCell {
    private let heading = UILabel(), metrics = UILabel(), retained = UILabel()
    private let bar = UIProgressView(progressViewStyle: .bar)
    init() {
        super.init(style: .default, reuseIdentifier: nil)
        heading.font = .preferredFont(forTextStyle: .headline); metrics.font = .preferredFont(forTextStyle: .subheadline)
        retained.font = .preferredFont(forTextStyle: .caption1); retained.textColor = .secondaryLabel
        [heading, metrics, retained].forEach { $0.numberOfLines = 0; $0.adjustsFontForContentSizeCategory = true }
        bar.progressTintColor = PlanningUI.accent; bar.trackTintColor = PlanningUI.accent.withAlphaComponent(0.1)
        let stack = UIStackView(arrangedSubviews: [heading, metrics, bar, retained]); stack.axis = .vertical; stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16), stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)])
        accessoryType = .disclosureIndicator
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(_ p: WorkloadPoint, days: Int, maxSeconds: Double, selected: Bool) {
        let percent = Int((p.retention * 100).rounded())
        heading.text = "\(percent)% retention" + (selected ? "  ·  Current" : "")
        metrics.text = String(format: "%.1f min/day   ·   %.0f reviews/day", p.seconds / Double(days) / 60, Double(p.reviews) / Double(days))
        retained.text = String(format: "≈ %.0f cards remembered at day %d  ·  %.1f cards/min", p.memorized, days, p.efficiency)
        bar.progress = Float(maxSeconds > 0 ? p.seconds / maxSeconds : 0)
        accessibilityIdentifier = "forecast.\(percent)"
    }
}
