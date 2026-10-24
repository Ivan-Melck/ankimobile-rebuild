import UIKit
import FlashcardsCore

final class AnkiSyncController: PlanningTableController {
    private let state: AnkiAppState
    private var busy = false {
        didSet { navigationItem.hidesBackButton = busy; navigationController?.interactivePopGestureRecognizer?.isEnabled = !busy }
    }
    private var message = "Sync this collection with AnkiWeb or your self-hosted server.", timer: Timer?
    init(state: AnkiAppState) { self.state = state; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Synchronize"; tableView.accessibilityIdentifier = "ankiSync"
        tableView.tableHeaderView = PlanningUI.hero(eyebrow: "Pick up where you left off", title: "One collection, everywhere", detail: "Cards, review history, presets, templates and media use Anki’s sync protocol.", symbol: "arrow.triangle.2.circlepath")
        tableView.rowHeight = UITableView.automaticDimension
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 2 ? 2 : 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { ["Status", nil, "Account"][section] }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { section == 2 ? "Your password is used only to sign in. The sync token is saved in this device’s Keychain. A full sync asks which copy to keep and creates a local backup first." : nil }
    override func tableView(_ tableView: UITableView, cellForRowAt p: IndexPath) -> UITableViewCell {
        if p.section == 0 { let c = PlanningUI.cell(message); c.textLabel?.numberOfLines = 0; c.selectionStyle = .none; return c }
        if p.section == 1 { let c = PlanningUI.cell(busy ? "Cancel synchronization" : "Synchronize now", symbol: busy ? "xmark.circle" : "arrow.triangle.2.circlepath"); c.textLabel?.textColor = PlanningUI.accent; c.accessibilityIdentifier = "ankiSyncNow"; return c }
        if p.row == 0 { return PlanningUI.cell("Sign in", symbol: "person.crop.circle", disclosure: true) }
        return PlanningUI.cell("Sign out", symbol: "rectangle.portrait.and.arrow.right")
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt p: IndexPath) {
        tableView.deselectRow(at: p, animated: true)
        if busy {
            if p.section == 1 { try? state.collection.backend.call("Sync", "AbortSync"); try? state.collection.backend.call("Sync", "AbortMediaSync") }; return
        }
        if p.section == 1 { synchronize() }
        if p.section == 2 && p.row == 0 { login() }
        if p.section == 2 && p.row == 1 { do { try state.saveAuth(nil); message = "Signed out on this device."; tableView.reloadData() } catch { showError(error) } }
    }
    private func login() {
        let alert = UIAlertController(title: "Sign in to synchronize", message: "Leave Server blank to use AnkiWeb.", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Email or username"; $0.textContentType = .username; $0.autocapitalizationType = .none; $0.autocorrectionType = .no }
        alert.addTextField { $0.placeholder = "Password"; $0.isSecureTextEntry = true; $0.textContentType = .password }
        alert.addTextField { $0.placeholder = "Server URL (optional)"; $0.keyboardType = .URL; $0.autocapitalizationType = .none; $0.autocorrectionType = .no }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Sign In", style: .default) { [weak self] _ in
            guard let self else { return }; let username = alert.textFields?[0].text ?? "", password = alert.textFields?[1].text ?? "", endpoint = alert.textFields?[2].text ?? ""
            self.run("Signing in…", work: { try self.state.collection.login(username: username, password: password, endpoint: endpoint.isEmpty ? nil : endpoint) }) { auth in
                do { try self.state.saveAuth(auth); self.message = "Signed in. Ready to synchronize."; self.tableView.reloadData() } catch { self.showError(error) }
            }
        }); present(alert, animated: true)
    }
    private func synchronize() {
        do { guard let auth = try state.auth() else { login(); return }
            run("Synchronizing collection…", work: { try self.state.collection.sync(auth: auth) }) { response in
                var auth = auth
                if response["newEndpoint"] != .null { auth["endpoint"] = response["newEndpoint"]; try? self.state.saveAuth(auth) }
                let required = response["required"].string
                if ["FULL_SYNC", "FULL_UPLOAD", "FULL_DOWNLOAD"].contains(required) { self.chooseFullSync(auth: auth, response: response) }
                else { self.waitForMedia() }
            }
        } catch { showError(error) }
    }
    private func chooseFullSync(auth: AnkiValue, response: AnkiValue) {
        let alert = UIAlertController(title: "Choose a collection copy", message: "A full sync is required. Download replaces this profile with the server copy. Upload replaces the server copy with this profile. A local backup is made before either action.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if response["required"].string != "FULL_UPLOAD" { alert.addAction(UIAlertAction(title: "Download Server Collection", style: .default) { [weak self] _ in self?.full(auth: auth, upload: false, response: response) }) }
        if response["required"].string != "FULL_DOWNLOAD" { alert.addAction(UIAlertAction(title: "Upload This Collection", style: .destructive) { [weak self] _ in self?.full(auth: auth, upload: true, response: response) }) }
        present(alert, animated: true)
    }
    private func full(auth: AnkiValue, upload: Bool, response: AnkiValue) {
        run(upload ? "Uploading collection…" : "Downloading collection…", work: {
            try self.state.collection.backend.call("Collection", "CreateBackup", ["backupFolder": .string(self.state.collection.directory.appendingPathComponent("backups").path), "force": .bool(true), "waitForCompletion": .bool(true)])
            try self.state.collection.fullSync(auth: auth, upload: upload, serverUSN: .number(Double(response["serverMediaUsn"].int)))
            return true
        }) { _ in self.waitForMedia() }
    }
    private func waitForMedia() {
        do { let status = try state.collection.backend.call("Sync", "MediaSyncStatus")
            if status["active"].bool {
                busy = true; message = "Synchronizing media…"; tableView.reloadData()
                timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in self?.waitForMedia() }
            } else { busy = false; message = "Synchronization complete."; tableView.reloadData() }
        } catch { busy = false; message = error.localizedDescription; tableView.reloadData() }
    }
    private func run<T>(_ text: String, work: @escaping () throws -> T, completion: @escaping (T) -> Void) {
        busy = true; message = text; tableView.reloadData()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result(catching: work)
            DispatchQueue.main.async { guard let self else { return }; self.busy = false
                switch result { case .success(let value): completion(value); case .failure(let error): self.message = error.localizedDescription }
                self.tableView.reloadData()
            }
        }
    }
    deinit { timer?.invalidate() }
}
