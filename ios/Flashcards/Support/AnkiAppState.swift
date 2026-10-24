import UIKit
import Security
import FlashcardsCore

final class AnkiAppState {
    var collection: AnkiCollection
    let profilesURL: URL
    private let activeProfileKey: String
    let preferences = UserDefaults.standard
    var onProfileChanged: (() -> Void)?
    init(root: URL, testing: Bool = false, reset: Bool = false) throws {
        activeProfileKey = testing ? "ankiTestActiveProfile" : "ankiActiveProfile"
        profilesURL = root.appendingPathComponent(testing ? "AnkiTestProfiles" : "AnkiProfiles", isDirectory: true)
        if testing && reset { try? FileManager.default.removeItem(at: profilesURL); preferences.removeObject(forKey: activeProfileKey) }
        let name = preferences.string(forKey: activeProfileKey) ?? "default"
        collection = try AnkiCollection(directory: profilesURL.appendingPathComponent(name, isDirectory: true))
        if testing && ProcessInfo.processInfo.arguments.contains("--anki-media-fixture") { try seedMediaFixture() }
        if testing && ProcessInfo.processInfo.arguments.contains("--anki-occlusion-fixture") { try seedOcclusionFixture() }
        if testing && ProcessInfo.processInfo.arguments.contains("--anki-rwkv-fixture") { try seedRWKVFixture() }
    }
    private func seedRWKVFixture() throws {
        let settings = try collection.deckConfiguration("1")
        var config = settings.selected, algorithm = config["config"], all = settings.all
        algorithm["rwkvReviewEnabled"] = .bool(false); algorithm["rwkvReviewInstantOrderEnabled"] = .bool(true); algorithm["fsrsVersion"] = .string("SIX")
        config["config"] = algorithm; all["fsrs"] = .bool(true)
        try collection.saveDeckConfiguration(config, deckID: "1", original: all)
        guard let basic = try collection.notetypes().first(where: { $0["name"].string == "Basic" }) else { throw CollectionError.invalidInput("Missing RWKV fixture type.") }
        _ = try collection.addNote(notetypeID: basic["id"].string, deckID: "1", fields: ["RWKV Instant on iOS", "Real Anki review history"])
    }
    private func seedMediaFixture(addNote: Bool = true) throws {
        try Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"80\" height=\"80\"><rect width=\"80\" height=\"80\" rx=\"16\" fill=\"#5856d6\"/></svg>".utf8).write(to: collection.mediaURL.appendingPathComponent("fixture.svg"))
        // A small valid PCM WAV; synthetic test data never enters real profiles.
        var wav = Data()
        func text(_ value: String) { wav.append(contentsOf: value.utf8) }
        func number(_ value: UInt32, _ bytes: Int) { for shift in 0..<bytes { wav.append(UInt8(truncatingIfNeeded: value >> (shift * 8))) } }
        text("RIFF"); number(836, 4); text("WAVEfmt "); number(16, 4); number(1, 2); number(1, 2); number(8000, 4); number(8000, 4); number(1, 2); number(8, 2); text("data"); number(800, 4); wav.append(Data(repeating: 128, count: 800))
        try wav.write(to: collection.mediaURL.appendingPathComponent("fixture.wav"))
        if addNote, let basic = try collection.notetypes().first(where: { $0["name"].string == "Basic" }) {
            let html = #"<img src="fixture.svg" alt="Fixture image" onload="this.insertAdjacentText('afterend','Image ready')"><audio src="fixture.wav" controls preload="auto" autoplay muted oncanplay="if(!this.dataset.ready){this.dataset.ready='1';this.insertAdjacentText('afterend','Audio ready')}"></audio><script>let active=0,finished=0;document.addEventListener('play',e=>{if(e.target.hasAttribute('data-anki-auto')){active++;if(active>1)document.body.append('Audio overlap')}},true);document.addEventListener('ended',e=>{if(e.target.hasAttribute('data-anki-auto')){active--;if(++finished===2)document.body.append('Sequence ready')}},true)</script>[sound:fixture.wav][sound:fixture.wav]"#
            let math = #"<div>\(x^2+1\) \(\ce{H2O}\)</div><script>addEventListener('load',()=>MathJax.startup.promise.then(()=>{if(document.querySelector('mjx-container svg')&&!document.querySelector('[data-mjx-error]'))document.body.append('Math ready')}))</script>"#
            _ = try collection.addNote(notetypeID: basic["id"].string, deckID: "1", fields: [html + math, "Synthetic media answer"])
        }
    }
    private func seedOcclusionFixture() throws {
        try seedMediaFixture(addNote: false)
        try collection.backend.call("ImageOcclusion", "AddImageOcclusionNotetype")
        guard let name = try collection.notetypes().first(where: { $0["name"].string == "Image Occlusion" }) else { throw CollectionError.invalidInput("Missing occlusion fixture type.") }
        var type = try collection.notetype(name["id"].string), templates = type["templates"].array
        let callback = #"anki.imageOcclusion.setup({onDidDrawShapes:(data,ctx)=>{const c=ctx.canvas;const alpha=ctx.getImageData(Math.floor(c.width*.35),Math.floor(c.height*.35),1,1).data[3];document.getElementById('io-status').append(data.activeShapes.length?(alpha?'Mask ready':'Mask missing'):'Answer masks ready')}});"#
        for i in templates.indices {
            var template = templates[i], config = template["config"]
            for key in ["qFormat", "aFormat"] { config[key] = .string(config[key].string.replacingOccurrences(of: "anki.imageOcclusion.setup();", with: callback)) }
            template["config"] = config; templates[i] = template
        }
        type["templates"] = .array(templates); try collection.backend.call("Notetypes", "UpdateNotetype", type.object)
        let indexes = try collection.backend.call("ImageOcclusion", "GetImageOcclusionFields", ["notetypeId": name["id"]])["fields"]
        var fields = Array(repeating: "", count: type["fields"].array.count)
        fields[indexes["occlusions"].int] = "{{c1::image-occlusion:rect:left=.2:top=.2:width=.5:height=.5}}"
        fields[indexes["image"].int] = "<img src=\"fixture.svg\">"
        fields[indexes["header"].int] = "<div id=\"io-status\"></div>"
        _ = try collection.addNote(notetypeID: name["id"].string, deckID: "1", fields: fields)
    }
    func useProfile(_ imported: AnkiCollection) {
        collection = imported; preferences.set(imported.directory.lastPathComponent, forKey: activeProfileKey); onProfileChanged?()
    }
    func applyAppearance(_ window: UIWindow?) { let value = preferences.integer(forKey: "appearance"); window?.overrideUserInterfaceStyle = value == 1 ? .light : value == 2 ? .dark : .unspecified }
    var authKey: String { "anki-sync-" + profilesURL.lastPathComponent + "-" + collection.directory.lastPathComponent }
    var rwkvModel: String {
        get { preferences.string(forKey: profilePreference("rwkvModel")) ?? "sm56" }
        set { preferences.set(newValue, forKey: profilePreference("rwkvModel")) }
    }
    var rwkvPrecision: String {
        get { preferences.string(forKey: profilePreference("rwkvPrecision")) ?? "cards_int4_notes_int8" }
        set { preferences.set(newValue, forKey: profilePreference("rwkvPrecision")) }
    }
    private func profilePreference(_ name: String) -> String { "anki-profile-\(profilesURL.lastPathComponent)-\(collection.directory.lastPathComponent)-\(name)" }
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
