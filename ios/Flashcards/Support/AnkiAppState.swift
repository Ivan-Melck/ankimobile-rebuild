import UIKit
import Security
import FlashcardsCore

final class AnkiAppState {
    var collection: AnkiCollection
    let profilesURL: URL
    let preferences = UserDefaults.standard
    var onProfileChanged: (() -> Void)?
    init(root: URL, testing: Bool = false, reset: Bool = false) throws {
        profilesURL = root.appendingPathComponent(testing ? "AnkiTestProfiles" : "AnkiProfiles", isDirectory: true)
        if testing && reset { try? FileManager.default.removeItem(at: profilesURL) }
        let name = testing ? "default" : (UserDefaults.standard.string(forKey: "ankiActiveProfile") ?? "default")
        collection = try AnkiCollection(directory: profilesURL.appendingPathComponent(name, isDirectory: true))
    }
    func useProfile(_ imported: AnkiCollection) {
        collection = imported; preferences.set(imported.directory.lastPathComponent, forKey: "ankiActiveProfile"); onProfileChanged?()
    }
    func applyAppearance(_ window: UIWindow?) { let value = preferences.integer(forKey: "appearance"); window?.overrideUserInterfaceStyle = value == 1 ? .light : value == 2 ? .dark : .unspecified }
    var authKey: String { "anki-sync-" + collection.directory.lastPathComponent }
    var rwkvModel: String {
        get { preferences.string(forKey: profilePreference("rwkvModel")) ?? "sm56" }
        set { preferences.set(newValue, forKey: profilePreference("rwkvModel")) }
    }
    var rwkvPrecision: String {
        get { preferences.string(forKey: profilePreference("rwkvPrecision")) ?? "cards_int4_notes_int8" }
        set { preferences.set(newValue, forKey: profilePreference("rwkvPrecision")) }
    }
    private func profilePreference(_ name: String) -> String { "anki-profile-\(collection.directory.lastPathComponent)-\(name)" }
    func auth() throws -> AnkiValue? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Flashcards.AnkiSync", kSecAttrAccount as String: authKey, kSecReturnData as String: true]
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CollectionError.invalidInput("Unable to read saved sync credentials.") }
        return try JSONDecoder().decode(AnkiValue.self, from: data)
    }
    func saveAuth(_ value: AnkiValue?) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Flashcards.AnkiSync", kSecAttrAccount as String: authKey]
        if let value {
            let data = try JSONEncoder().encode(value)
            let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if update == errSecItemNotFound {
                var add = query; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw CollectionError.invalidInput("Unable to save sync credentials.") }
            } else if update != errSecSuccess { throw CollectionError.invalidInput("Unable to update sync credentials.") }
        } else { SecItemDelete(query as CFDictionary) }
    }
}

extension UIViewController {
    func ankiWork<T>(_ work: @escaping () throws -> T, completion: @escaping (T) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result(catching: work)
            DispatchQueue.main.async { guard let self else { return }; switch result { case .success(let value): completion(value); case .failure(let error): self.showError(error) } }
        }
    }
}
