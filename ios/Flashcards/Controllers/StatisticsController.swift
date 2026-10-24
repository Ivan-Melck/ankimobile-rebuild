import UIKit
import FlashcardsCore

final class StatisticsController: UITableViewController {
    private let model: AppModel
    private let deckID: UUID?
    private var rows: [(String, String)] = []
    init(model: AppModel, deckID: UUID? = nil) { self.model = model; self.deckID = deckID; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("Use init(model:deckID:)") }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated); title = "Statistics"
        navigationController?.setToolbarHidden(true, animated: animated)
        let stats = model.store.statistics(deckID: deckID)
        rows = [("Total Cards", "\(stats.totalCards)"), ("New", "\(stats.newCards)"), ("Learning", "\(stats.learningCards)"), ("Review", "\(stats.reviewCards)"), ("Suspended", "\(stats.suspendedCards)"), ("Due Now", "\(stats.dueCards)"), ("Answers Today", "\(stats.reviewsToday)"), ("Correct Answers", "\(Int((stats.retention * 100).rounded()))%"), ("Time Today", "\(Int(stats.reviewSecondsToday)) seconds")]
        tableView.reloadData()
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = rows[indexPath.row].0; cell.detailTextLabel?.text = rows[indexPath.row].1; cell.selectionStyle = .none
        return cell
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { "Correct answers are Hard, Good, or Easy as a percentage of all recorded answers. Due counts respect daily limits." }
}
