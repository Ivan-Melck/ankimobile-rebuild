import UIKit
import FlashcardsCore

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        self.window = window
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            if testing { UserDefaults.standard.removeObject(forKey: "appearance") }
            let collectionURL = directory.appendingPathComponent(testing ? "ui-test-collection.json" : "collection.json")
            if ProcessInfo.processInfo.arguments.contains("--reset-test-collection"), FileManager.default.fileExists(atPath: collectionURL.path) { try FileManager.default.removeItem(at: collectionURL) }
            let fresh = !FileManager.default.fileExists(atPath: collectionURL.path)
            let store = try CollectionStore(fileURL: collectionURL)
            if fresh { var options = DeckOptions(); options.scheduling = SchedulingOptions(); try store.updateDeckOptions(id: store.defaultDeckID, options: options) }
            let model = AppModel(store: store)
            let navigation = UINavigationController(rootViewController: DecksController(model: model))
            navigation.navigationBar.prefersLargeTitles = false
            window.rootViewController = navigation
            model.applyAppearance(to: window)
        } catch {
            let controller = UIViewController()
            controller.view.backgroundColor = .systemBackground
            window.rootViewController = controller
            DispatchQueue.main.async {
                controller.showError(error, title: "Could Not Open Collection")
            }
        }
        window.makeKeyAndVisible()
        return true
    }
}
