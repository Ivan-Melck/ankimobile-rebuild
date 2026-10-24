import UIKit
import FlashcardsCore

final class AppModel {
    let store: CollectionStore
    let preferences = UserDefaults.standard
    init(store: CollectionStore) { self.store = store }

    var appearance: Int {
        get { preferences.integer(forKey: "appearance") }
        set { preferences.set(newValue, forKey: "appearance") }
    }
    var textSize: Double {
        get { let value = preferences.double(forKey: "reviewTextSize"); return value == 0 ? 24 : value }
        set { preferences.set(newValue, forKey: "reviewTextSize") }
    }
    func applyAppearance(to window: UIWindow?) {
        window?.overrideUserInterfaceStyle = appearance == 1 ? .light : appearance == 2 ? .dark : .unspecified
    }
}

enum Theme {
    static let new = UIColor(red: 36 / 255, green: 111 / 255, blue: 225 / 255, alpha: 1)
    static let learning = UIColor.systemRed
    static let review = UIColor(red: 0, green: 0.652, blue: 0.0655, alpha: 1)

    static func button(_ title: String, identifier: String, action: UIAction) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityIdentifier = identifier
        button.addAction(action, for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        return button
    }
}

extension UIViewController {
    func showError(_ error: Error, title: String = "Unable to Complete Action") {
        let alert = UIAlertController(title: title, message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    func showMessage(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    func shareFile(_ url: URL, from item: UIBarButtonItem? = nil) {
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            if let item = item { popover.barButtonItem = item }
            else { popover.sourceView = view; popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1) }
        }
        present(sheet, animated: true)
    }
}
