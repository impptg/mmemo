import Foundation
@main struct StorageCheck {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TaskStore(directory: directory)
        let empty = try store.load(); assert(empty.isEmpty)
        let task = Todo(id: "a", title: "周会 PPT", due: "", done: false)
        try store.save([task])
        let loaded = try store.load(); assert(loaded.first?.title == "周会 PPT")
        try store.save([Todo(id: "a", title: "周会 PPT", due: "", done: true)])
        let completed = try store.load(); assert(completed.first?.done == true)
        let backup = try Data(contentsOf: directory.appendingPathComponent("todos.backup.json"))
        let backedUp = try JSONDecoder().decode([Todo].self, from: backup); assert(backedUp.first?.done == false)
        try store.setDone(id: "a", done: false)
        let reopened = try store.load(); assert(reopened == [task])
        try store.setDone(id: "a", done: true)
        let checked = try store.load(); assert(checked.first?.done == true && checked.first?.title == task.title)
        do { try store.setDone(id: "missing", done: true); fatalError("Missing ID must fail") } catch {}
        let unchanged = try store.load(); assert(unchanged == checked)
        try Data("broken".utf8).write(to: store.file)
        do { _ = try store.load(); fatalError("Corrupt data must not be treated as empty") } catch {}
        let preserved = try String(contentsOf: store.file, encoding: .utf8); assert(preserved == "broken")
        var invalidDateRejected = false
        do { try store.validate([Todo(id: "bad-date", title: "时间验证", due: "2026-02-30T15:00", done: false)]) }
        catch { invalidDateRejected = true }
        assert(invalidDateRejected, "Native write boundary must reject impossible dates")
        print("PASS: empty store, real disk save/reload, last-good backup, corrupt data preservation")
    }
}
