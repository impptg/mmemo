import Foundation

@main struct DraftTests {
    static func main() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let draft:[String:Any]=["version":1,"parts":[["kind":"text","text":"未发送\n中文 😀 <script>"],["kind":"task","id":"test-id","title":"事项引用"]]]
        try ComposerDraft.save(draft,directory:directory)
        let loaded=try ComposerDraft.load(directory:directory)
        precondition(NSDictionary(dictionary:loaded).isEqual(to:draft))
        let file=directory.appendingPathComponent("composer-draft.json")
        let permissions=try FileManager.default.attributesOfItem(atPath:file.path)[.posixPermissions] as! NSNumber
        precondition(permissions.intValue == 0o600)
        for bad:Any in [["version":1,"parts":[["kind":"html","text":"<img onerror=alert(1)>"]]], ["version":1,"parts":[["kind":"text","text":"safe","html":"bad"]]], ["version":1,"parts":[["kind":"text","text":String(repeating:"x",count:131073)]]]] {
            do {try ComposerDraft.save(bad,directory:directory);fatalError("Invalid draft accepted")}
            catch {let unchanged=try ComposerDraft.load(directory:directory);precondition(NSDictionary(dictionary:unchanged).isEqual(to:draft))}
        }
        try ComposerDraft.save(["version":1,"parts":[[String:String]]()],directory:directory)
        let cleared=try ComposerDraft.load(directory:directory)
        precondition(cleared["parts"] as! [[String:String]] == [])
        print("PASS: Unicode/reference roundtrip, permissions, validation, previous-data preservation, clear")
    }
}
