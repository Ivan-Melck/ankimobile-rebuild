import UIKit
import FlashcardsCore

final class CalibrationController: PlanningTableController {
    private let model: AppModel; private let deckID: UUID
    private var busy = false, timeSeries = false
    private var result: CalibrationResult?, parameters: [Double]?, message: String?
    private var settings: SchedulingOptions { model.store.schedulingOptions(deckID: deckID) }
    init(model: AppModel, deckID: UUID) { self.model = model; self.deckID = deckID; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Model Insights"; tableView.accessibilityIdentifier = "modelInsights"
        tableView.rowHeight = UITableView.automaticDimension; tableView.estimatedRowHeight = 52
        tableView.tableHeaderView = PlanningUI.hero(eyebrow: "Learn from your history", title: "How well does it predict?", detail: "Check recall predictions, then personalize FSRS when you have enough reviews.", symbol: "chart.xyaxis.line")
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 3 : section == 1 ? (result == nil ? 1 : 3) : (parameters == nil ? 1 : 2) }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { ["Prediction check", "Results", "Personalize FSRS"][section] }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return settings.engine.isRWKV ? "RWKV evaluation replays your history causally with the selected weights. Time-series fitting is for FSRS." : "Final-fit uses your current parameters. Time-series validation trains on earlier reviews and checks later ones, so it takes longer." }
        if section == 1 { return "Lower log loss and calibration error are better. Calibration is reported as RMSE across recall bins. A small sample is uncertain." }
        return "Optimization needs at least 100 follow-up reviews. Results are previewed before applying. The saved backup includes your custom parameters."
    }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        if p.section == 0 {
            if p.row == 0 { return PlanningUI.cell("Active model", value: settings.engine.title, symbol: "brain") }
            if p.row == 1, settings.engine.isRWKV { let c = PlanningUI.cell("Evaluation", value: "Causal replay"); c.selectionStyle = .none; return c }
            if p.row == 1 { return PlanningUI.toggle("Time-series validation", value: timeSeries, id: "timeSeriesValidation") { [weak self] value in self?.timeSeries = value; self?.result = nil; self?.message = nil; self?.tableView.reloadData() } }
            let cell = PlanningUI.cell(busy ? "Working…" : "Evaluate predictions", symbol: "waveform.path.ecg"); cell.accessibilityIdentifier = "evaluatePredictions"; cell.textLabel?.textColor = PlanningUI.accent; return cell
        }
        if p.section == 1 {
            guard let result else { let c = PlanningUI.cell(message ?? "Run a prediction check to see results."); c.textLabel?.textColor = .secondaryLabel; c.selectionStyle = .none; return c }
            return PlanningUI.cell(["Log loss", "Calibration error", "Follow-up reviews"][p.row], value: p.row == 0 ? String(format: "%.4f", result.log_loss) : p.row == 1 ? String(format: "%.2f%%", result.rmse * 100) : String(result.samples))
        }
        if p.row == 0 { let c = PlanningUI.cell(busy ? "Working…" : "Optimize parameters", value: settings.parameters.isEmpty ? "Defaults" : "Personalized", symbol: "wand.and.stars"); c.accessibilityIdentifier = "optimizeParameters"; c.textLabel?.textColor = PlanningUI.accent; return c }
        let c = PlanningUI.cell("Apply \(parameters?.count ?? 0) fitted parameters", symbol: "checkmark.circle"); c.textLabel?.textColor = PlanningUI.accent; return c
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        tableView.deselectRow(at: p, animated: true); guard !busy else { return }
        if p.section == 0 && p.row == 2 { run(optimize: false) }
        if p.section == 2 && p.row == 0 { run(optimize: true) }
        if p.section == 2 && p.row == 1, let parameters, var options = model.store.decks.first(where: { $0.id == deckID })?.options {
            var value = settings; value.parameters = parameters; options.scheduling = value; options.presetID = nil
            do { try model.store.updateDeckOptions(id: deckID, options: options); self.parameters = nil; result = nil; message = "Personalized parameters saved for future reviews."; tableView.reloadData() } catch { showError(error) }
        }
    }
    private func run(optimize: Bool) {
        busy = true; message = nil; result = nil; parameters = nil; tableView.reloadData()
        let validation = timeSeries
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let fitted = optimize ? try self.model.store.optimize(deckID: self.deckID) : nil
                let evaluation = optimize ? nil : try self.model.store.evaluate(deckID: self.deckID, timeSeries: validation)
                DispatchQueue.main.async { self.parameters = fitted; self.result = evaluation; self.busy = false; self.message = fitted == nil ? nil : "Fit complete. Apply the parameters below when you’re ready."; self.tableView.reloadData() }
            } catch { DispatchQueue.main.async { self.busy = false; self.message = error.localizedDescription; self.tableView.reloadData() } }
        }
    }
}

final class CardInsightsController: PlanningTableController {
    private let model: AppModel; private let cardID: UUID
    private var prediction: MemoryPrediction?, failure: String?
    init(model: AppModel, cardID: UUID) { self.model = model; self.cardID = cardID; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Card Insights"
        tableView.tableHeaderView = PlanningUI.hero(eyebrow: "Behind the next review", title: "A picture of your memory", detail: "Predictions change with elapsed time and the answers you give.", symbol: "brain.head.profile")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }; let result = Result { try self.model.store.prediction(cardID: self.cardID) }
            DispatchQueue.main.async { switch result { case .success(let value): self.prediction = value; case .failure(let error): self.failure = error.localizedDescription }; self.tableView.reloadData() }
        }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { prediction == nil ? (section == 0 ? 1 : 0) : (section == 0 ? 3 : 4) }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 0 ? "Right now" : "Next interval by answer" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { section == 1 ? "Raw model intervals before same-day and queue settings. Stability is the memory timescale in days; RWKV reports its 90% recall interval." : nil }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        guard let value = prediction else { return PlanningUI.cell(failure ?? "Reading your review history…") }
        if p.section == 0 {
            if p.row == 0 { return PlanningUI.cell("Predicted recall", value: value.retrievability.map { String(format: "%.1f%%", $0 * 100) } ?? "New card") }
            if p.row == 1 { return PlanningUI.cell("Stability", value: value.stability.map { String(format: "%.2f days", $0) } ?? "—") }
            return PlanningUI.cell("Difficulty", value: value.difficulty.map { String(format: "%.1f / 10", $0) } ?? "Neural model")
        }
        let days = value.intervals[p.row] ?? 0
        return PlanningUI.cell(ReviewRating.allCases[p.row].displayName, value: days < 1 / 1440 ? String(format: "%.0f sec", max(1, days * 86400)) : days < 1 ? String(format: "%.0f min", days * 1440) : String(format: "%.1f days", days))
    }
}
