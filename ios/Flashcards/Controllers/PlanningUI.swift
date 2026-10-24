import UIKit
import FlashcardsCore

enum PlanningUI {
    static let accent = UIColor.systemIndigo
    static func cell(_ title: String, value: String? = nil, symbol: String? = nil, disclosure: Bool = false) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = title; cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.text = value; cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        if let symbol { cell.imageView?.image = UIImage(systemName: symbol); cell.imageView?.tintColor = accent }
        cell.accessoryType = disclosure ? .disclosureIndicator : .none
        return cell
    }
    static func toggle(_ title: String, value: Bool, id: String, change: @escaping (Bool) -> Void) -> UITableViewCell {
        let cell = self.cell(title)
        let control = UISwitch(); control.isOn = value; control.onTintColor = accent
        control.accessibilityIdentifier = id; control.accessibilityLabel = title
        control.addAction(UIAction { _ in change(control.isOn) }, for: .valueChanged)
        cell.accessoryView = control; cell.selectionStyle = .none
        return cell
    }
    static func hero(eyebrow: String, title: String, detail: String, symbol: String) -> UIView {
        let outer = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 188))
        let card = UIView(); card.backgroundColor = accent.withAlphaComponent(0.09); card.layer.cornerRadius = 22
        card.translatesAutoresizingMaskIntoConstraints = false; outer.addSubview(card)
        let icon = UIImageView(image: UIImage(systemName: symbol)); icon.tintColor = accent
        icon.contentMode = .scaleAspectFit; icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
        let label = UILabel(); label.text = eyebrow.uppercased(); label.font = .preferredFont(forTextStyle: .caption1); label.textColor = accent
        let top = UIStackView(arrangedSubviews: [icon, label]); top.spacing = 9; top.alignment = .center
        let heading = UILabel(); heading.text = title; heading.font = .preferredFont(forTextStyle: .title1); heading.numberOfLines = 0
        let subtitle = UILabel(); subtitle.text = detail; subtitle.numberOfLines = 0; subtitle.font = .preferredFont(forTextStyle: .subheadline); subtitle.textColor = .secondaryLabel
        [label, heading, subtitle].forEach { $0.adjustsFontForContentSizeCategory = true }
        let stack = UIStackView(arrangedSubviews: [top, heading, subtitle]); stack.axis = .vertical; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(stack)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: outer.leadingAnchor, constant: 20), card.trailingAnchor.constraint(equalTo: outer.trailingAnchor, constant: -20),
            card.topAnchor.constraint(equalTo: outer.topAnchor, constant: 16), card.bottomAnchor.constraint(equalTo: outer.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18), stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])
        return outer
    }
}

final class PlanningChoiceController: UITableViewController {
    private let values: [(String, String)]
    private let selected: Int
    private let choose: (Int) -> Void
    init(title: String, values: [(String, String)], selected: Int, choose: @escaping (Int) -> Void) {
        self.values = values; self.selected = selected; self.choose = choose
        super.init(style: .insetGrouped); self.title = title
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() { super.viewDidLoad(); tableView.rowHeight = UITableView.automaticDimension; tableView.estimatedRowHeight = 76 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { values.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = values[indexPath.row].0; cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
        cell.detailTextLabel?.text = values[indexPath.row].1; cell.detailTextLabel?.numberOfLines = 0
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .subheadline); cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = selected == indexPath.row ? .checkmark : .none; cell.tintColor = PlanningUI.accent
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { choose(indexPath.row); navigationController?.popViewController(animated: true) }
}

extension UIViewController {
    func planningInput(title: String, message: String? = nil, value: String = "", numeric: Bool = false, save: @escaping (String) throws -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { $0.text = value; $0.keyboardType = numeric ? .decimalPad : .default; $0.accessibilityIdentifier = "planningInput" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            do { try save(alert.textFields?.first?.text ?? "") } catch { self?.showError(error) }
        })
        present(alert, animated: true)
    }
}

/// Table headers size themselves to readable text, including accessibility sizes.
class PlanningTableController: UITableViewController {
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = tableView.tableHeaderView else { return }
        let size = header.systemLayoutSizeFitting(CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        let height = max(120, ceil(size.height))
        if abs(header.frame.height - height) > 1 {
            header.frame.size.height = height; tableView.tableHeaderView = header
        }
    }
}
