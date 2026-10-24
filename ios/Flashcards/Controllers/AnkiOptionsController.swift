import UIKit
import FlashcardsCore

final class AnkiOptionsController: PlanningTableController {
    let state: AnkiAppState, deckID: String
    private var original: AnkiValue = .null, selected: AnkiValue = .null
    private var groups: [[AnkiValue]] = []
    private let globalToggles = [("Allow same-day scheduling", "fsrsShortTermWithStepsEnabled"), ("Skip learning/relearning queues", "fsrsLearningQueuesDisabled"), ("New cards ignore review limit", "newCardsIgnoreReviewLimit"), ("Apply all parent limits", "applyAllParentLimits"), ("Balance future review load", "loadBalancerEnabled")]
    private let names = ["Learning", "Daily limits & order", "Memory & retention", "RWKV", "Review experience", "Advanced"]
    init(state: AnkiAppState, deckID: String) { self.state = state; self.deckID = deckID; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Deck Options"; tableView.accessibilityIdentifier = "ankiOptions"
        tableView.rowHeight = UITableView.automaticDimension; tableView.estimatedRowHeight = 54
        do {
            let config = try state.collection.deckConfiguration(deckID); original = config.all; selected = config.selected
            let fields = try AnkiBackend.schema("anki.deck_config.DeckConfig.Config")["fields"].array.filter { $0["kind"].string != "bytes" }
            groups = Array(repeating: [], count: names.count)
            for field in fields {
                let key = field["name"].string
                let group: Int
                if key.hasPrefix("rwkv") { group = 3 }
                else if key.contains("Steps") || key.contains("Leech") || key.contains("Lapse") || key.contains("Graduating") { group = 0 }
                else if key.hasPrefix("fsrs") || key.lowercased().contains("retention") || key.contains("Search") { group = 2 }
                else if key.contains("Order") || key.contains("Mix") || key.contains("PerDay") || key.hasPrefix("bury") { group = 1 }
                else if key.lowercased().contains("timer") || key.contains("Autoplay") || key.contains("Answer") || key.contains("Question") || key.contains("Audio") { group = 4 }
                else { group = 5 }
                groups[group].append(field)
            }
            tableView.tableHeaderView = PlanningUI.hero(eyebrow: "Shared scheduling preset", title: selected["name"].string, detail: "Edits update this preset across linked decks. Imported fields and custom settings remain intact.", symbol: "slider.horizontal.3")
        } catch { showError(error) }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { groups.isEmpty ? 0 : groups.count + 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 3 + globalToggles.count : groups[section - 1].count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 0 ? "Collection scheduling" : names[section - 1] }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { section == 0 ? "RWKV model weights and precision are local profile settings on desktop as well. Match them to the desktop profile you review with." : nil }
    private func label(_ name: String) -> String {
        if name == "rwkvReviewEnabled" { return "Use RWKV Curve for due dates" }
        if name == "rwkvReviewInstantOrderEnabled" { return "Use RWKV Instant review order" }
        return name.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).replacingOccurrences(of: "rwkv", with: "RWKV").replacingOccurrences(of: "fsrs", with: "FSRS").capitalized
    }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        if p.section == 0 {
            if p.row >= 3 { let setting = globalToggles[p.row - 3]; return PlanningUI.toggle(setting.0, value: original[setting.1].bool, id: "ankiGlobal.\(setting.1)") { [weak self] value in guard let self else { return }; var source = self.original; source[setting.1] = .bool(value); self.save(self.selected, source: source) } }
            if p.row == 0 { return PlanningUI.toggle("Enable FSRS / RWKV scheduling", value: original["fsrs"].bool, id: "ankiFSRS") { [weak self] value in guard let self else { return }; var source = self.original; source["fsrs"] = .bool(value); self.save(self.selected, source: source) } }
            if p.row == 1 { return PlanningUI.cell("RWKV model", value: state.rwkvModel.uppercased(), disclosure: true) }
            return PlanningUI.cell("RWKV state precision", value: state.rwkvPrecision, disclosure: true)
        }
        let field = groups[p.section - 1][p.row], key = field["name"].string, value = selected["config"][key]
        if field["kind"].string == "bool" { return PlanningUI.toggle(label(key), value: value.bool, id: "ankiOption.\(key)") { [weak self] enabled in self?.set(key, .bool(enabled)) } }
        let text = field["repeated"].bool ? "\(value.array.count) values" : value == .null ? "Default" : value.string
        return PlanningUI.cell(label(key), value: text, disclosure: true)
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        tableView.deselectRow(at: p, animated: true)
        if p.section == 0 {
            guard p.row > 0, p.row < 3 else { return }
            let values = p.row == 1 ? ["sm56", "sm55", "sm40", "sm36", "legacy"] : ["cards_int4_notes_int8", "f32", "int8", "int4"]
            let current = p.row == 1 ? state.rwkvModel : state.rwkvPrecision
            navigationController?.pushViewController(PlanningChoiceController(title: p.row == 1 ? "RWKV Model" : "State Precision", values: values.map { ($0, "") }, selected: values.firstIndex(of: current) ?? 0) { [weak self] i in if p.row == 1 { self?.state.rwkvModel = values[i] } else { self?.state.rwkvPrecision = values[i] }; self?.tableView.reloadData() }, animated: true); return
        }
        let field = groups[p.section - 1][p.row], key = field["name"].string, value = selected["config"][key]
        if field["kind"].string == "bool" { return }
        if field["kind"].string == "enum" {
            let values = field["values"].array.map(\.string)
            navigationController?.pushViewController(PlanningChoiceController(title: label(key), values: values.map { ($0.replacingOccurrences(of: "_", with: " ").capitalized, "") }, selected: values.firstIndex(of: value.string) ?? 0) { [weak self] i in self?.set(key, .string(values[i])) }, animated: true)
        } else {
            planningInput(title: label(key), message: field["repeated"].bool ? "Separate values with commas." : nil, value: field["repeated"].bool ? value.array.map { $0.string }.joined(separator: ", ") : value.string) { [weak self] text in
                guard let self else { return }
                if field["repeated"].bool {
                    let numbers = try text.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map { string -> AnkiValue in guard let n = Double(string), n.isFinite else { throw CollectionError.invalidInput("Enter numbers separated by commas.") }; return .number(n) }
                    self.set(key, .array(numbers))
                } else if field["kind"].string == "number" { guard let n = Double(text), n.isFinite else { throw CollectionError.invalidInput("Enter a finite number.") }; self.set(key, .number(n)) }
                else { self.set(key, .string(text)) }
            }
        }
    }
    private func set(_ key: String, _ value: AnkiValue) { var next = selected, config = next["config"]; config[key] = value; next["config"] = config; save(next, source: original) }
    private func save(_ value: AnkiValue, source: AnkiValue) {
        do { try state.collection.saveDeckConfiguration(value, deckID: deckID, original: source); selected = value; original = source; tableView.reloadData() } catch { showError(error) }
    }
}
