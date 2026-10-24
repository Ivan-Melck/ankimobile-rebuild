import UIKit
import FlashcardsCore

final class DecksController: PlanningTableController {
    private let model: AppModel
    private var decks: [Deck] { model.store.decks.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    init(model: AppModel) { self.model = model; super.init(style: .plain) }
    required init?(coder: NSCoder) { fatalError("Use init(model:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Decks"
        tableView.accessibilityIdentifier = "deckList"
        tableView.register(DeckCell.self, forCellReuseIdentifier: "deck")
        tableView.rowHeight = 51
        let statistics = UIBarButtonItem(image: UIImage(systemName: "chart.bar"), style: .plain, target: self, action: #selector(statistics))
        statistics.accessibilityLabel = "Statistics"
        let plan = UIBarButtonItem(image: UIImage(systemName: "sparkles"), style: .plain, target: self, action: #selector(studyPlan))
        plan.accessibilityLabel = "Study Plan"
        navigationItem.leftBarButtonItems = [plan, statistics]
        tableView.tableHeaderView = PlanningUI.hero(eyebrow: "Make room for remembering", title: "A little every day", detail: "Study your decks, or shape tomorrow’s workload in Study Plan.", symbol: "rectangle.stack")
        let preferences = UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: self, action: #selector(settings))
        preferences.accessibilityLabel = "Settings"
        navigationItem.rightBarButtonItems = [preferences, UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(browse))]
        let sync = UIBarButtonItem(title: "Synchronize", style: .plain, target: self, action: #selector(sync))
        sync.accessibilityIdentifier = "synchronize"
        toolbarItems = [UIBarButtonItem(title: "Add/Export", style: .plain, target: self, action: #selector(tools)), .flexibleSpace(), sync]
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(refreshDecks), for: .valueChanged)
        refreshControl = refresh
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
        tableView.reloadData()
    }
    @objc private func refreshDecks() { tableView.reloadData(); refreshControl?.endRefreshing() }
    @objc private func studyPlan() { navigationController?.pushViewController(StudyPlanController(model: model), animated: true) }
    @objc private func settings() { navigationController?.pushViewController(SettingsController(model: model), animated: true) }
    @objc private func browse() { navigationController?.pushViewController(BrowserController(model: model), animated: true) }
    @objc private func statistics() { navigationController?.pushViewController(StatisticsController(model: model), animated: true) }
    @objc private func help() {
        showMessage("Flashcards", "Tap a deck to study. Add notes from Add/Export or the study screen. Tap a card or Show Answer to reveal it, then choose Again, Hard, Good, or Easy. Swipe a deck for options. Browse lets you search and edit cards.")
    }
    @objc private func tools() { navigationController?.pushViewController(ToolsController(model: model), animated: true) }
    @objc private func sync() {
        showMessage("Local Collection", "AnkiWeb synchronization is not implemented in this rebuild. Use Tools to import CSV or export your collection backup.")
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { decks.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let deck = decks[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "deck", for: indexPath) as! DeckCell
        let counts = model.store.deckCounts(deckID: deck.id)
        cell.configure(name: deck.name, new: counts.new, learning: counts.learning, review: counts.review)
        cell.accessibilityIdentifier = "deck.\(deck.id.uuidString)"
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(ReviewerController(model: model, deck: decks[indexPath.row]), animated: true)
    }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deck = decks[indexPath.row]
        let options = UIContextualAction(style: .normal, title: "Options") { [weak self] _, _, done in
            guard let self = self else { done(false); return }
            self.navigationController?.pushViewController(DeckOptionsController(model: self.model, deck: deck), animated: true)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [options])
    }
}

private final class DeckCell: UITableViewCell {
    private let nameLabel = UILabel()
    private let counts = UIStackView()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.numberOfLines = 2
        counts.axis = .vertical; counts.spacing = 1; counts.alignment = .trailing
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        counts.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel); contentView.addSubview(counts)
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: counts.leadingAnchor, constant: -12),
            counts.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            counts.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        accessoryType = .disclosureIndicator
    }
    required init?(coder: NSCoder) { fatalError("Use init(style:reuseIdentifier:)") }
    func configure(name: String, new: Int, learning: Int, review: Int) {
        nameLabel.text = name
        counts.arrangedSubviews.forEach { counts.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (value, color) in [(review + learning, Theme.review), (new, Theme.new)] {
            let label = UILabel(); label.text = String(value); label.textColor = color
            label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            counts.addArrangedSubview(label)
        }
        isAccessibilityElement = true
        accessibilityLabel = "\(name), \(new) new, \(learning) learning, \(review) review"
    }
}
