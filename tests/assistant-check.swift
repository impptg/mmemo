import Foundation
@main struct AICheck {
    static func decode(_ json: String) throws -> AIReply { try JSONDecoder().decode(AIReply.self, from: Data(json.utf8)) }
    static func main() async throws {
        setbuf(stdout, nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mmemo-ai-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TaskStore(directory: directory)
        let initial = [Todo(id: "a", title: "周报", due: "2026-09-18T15:00", done: false)]
        try store.save(initial)
        let update = try decode(#"{"reply":"已完成","changes":[{"action":"update","id":"a","done":true}]}"#)
        let partner = Todo(id:"a", title:"周报", due:"", done:false, member:"partner")
        let partnerUpdate = try update.applying(to:[partner], store:store)
        assert(partnerUpdate[0].member == "partner")
        let roundTrip = try JSONDecoder().decode(Todo.self, from: JSONEncoder().encode(partner))
        assert(roundTrip.member == "partner")
        let legacy = try JSONDecoder().decode(Todo.self, from: Data(#"{"id":"legacy","title":"旧待办","due":"","done":false}"#.utf8))
        assert(legacy.member == nil)
        let updated = try update.applying(to: initial, store: store)
        assert(updated[0].done && updated[0].title == "周报" && updated[0].due == "2026-09-18T15:00")
        for json in [
            #"{"reply":"bad","changes":[{"action":"update","id":"missing","done":true}]}"#,
            #"{"reply":"bad","changes":[{"action":"create","title":"正常","due":""},{"action":"update","id":"a","due":"2026-02-30T12:00"}]}"#,
            #"{"reply":"bad","changes":[{"action":"update","id":"a","done":true},{"action":"delete","id":"a"}]}"#,
            #"{"reply":"bad","changes":[{"action":"create","id":"a","title":"覆盖"}]}"#,
            #"{"reply":"bad","changes":[{"action":"update","id":"a","title":" "}]}"#,
            #"{"reply":"bad","changes":[{"action":"create","title":"遗漏日期"}]}"#
        ] {
            var rejected = false
            do { let next = try decode(json).applying(to: initial, store: store); try store.save(next) } catch { rejected=true }
            assert(rejected, "Invalid model operations must fail atomically")
            let unchanged = try store.load(); assert(unchanged == initial)
        }
        let created = try decode(#"{"reply":"已记录","changes":[{"action":"create","title":"新任务","due":""}]}"#).applying(to: initial, store: store)
        assert(created.count == 2 && created[1].id != "a" && !created[1].done)
        let deleted = try decode(#"{"reply":"已删除","changes":[{"action":"delete","id":"a"}]}"#).applying(to: initial, store: store)
        assert(deleted.isEmpty)
        assert(update.receipt(before: initial, after: updated).contains("2026-09-18 15:00"))
        let ids=["2100541450115510274","2100541456125558785"]
        let bothJSON="{\"reply\":\"已记录\",\"changes\":[{\"action\":\"create\",\"title\":\"一起买菜\",\"due\":\"\",\"participants\":[\"\(ids[0])\",\"\(ids[1])\"]}]}"
        let both=try decode(bothJSON).applying(to:[],store:store)
        assert(both[0].participants==ids)
        try store.save(both);try store.setDone(id:both[0].id,done:true)
        let doneBoth=try store.load();assert(doneBoth[0].done && doneBoth[0].participants==ids)
        let personJSON="{\"reply\":\"改为一个人\",\"changes\":[{\"action\":\"update\",\"id\":\"\(both[0].id)\",\"participants\":[\"\(ids[1])\"]}]}"
        let person=try decode(personJSON).applying(to:both,store:store)
        assert(person[0].participants==[ids[1]] && person[0].title==both[0].title)
        for invalid in [[],[ids[0],ids[0]],["unknown"]] {
            let data=try JSONSerialization.data(withJSONObject:["reply":"bad","changes":[["action":"create","title":"bad","due":"","participants":invalid]]])
            var rejected=false
            do {_ = try JSONDecoder().decode(AIReply.self,from:data).applying(to:[],store:store)} catch {rejected=true}
            assert(rejected,"invalid participants must fail")
        }
        print("PASS: create, patch preserves fields, delete, invalid IDs/dates/duplicate mutations rejected atomically")
        if CommandLine.arguments.contains("--live") {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("mmemo")
            let assistant = TodoAssistant(config: try AIConfiguration.load(directory: base))
            let greeting = try await assistant.respond(to: "你好，只回复一句话，不要新增待办", tasks: [], history: [])
            assert(greeting.changes.isEmpty); print("PASS: live model canary (no user data)")
            let added = try await assistant.respond(to: "新增待办：联调测试。时间为2026年9月18日15点。", tasks: [], history: [])
            let newTasks = try added.applying(to: [], store: store)
            print("Live create reply:", added.reply, String(data: try JSONEncoder().encode(newTasks), encoding: .utf8)!)
            assert(newTasks.count == 1 && newTasks[0].title.contains("联调测试") && newTasks[0].due == "2026-09-18T15:00")
            try store.save(newTasks)
            let finish = try await assistant.respond(to: "把联调测试标记完成", tasks: try store.load(), history: [])
            let finished = try finish.applying(to: try store.load(), store: store)
            assert(finished.count == 1 && finished[0].done); try store.save(finished)
            let remove = try await assistant.respond(to: "删除联调测试", tasks: try store.load(), history: [])
            let removed = try remove.applying(to: try store.load(), store: store)
            assert(removed.isEmpty); try store.save(removed)
            print("PASS: live model create -> disk -> complete -> disk -> delete; 4 total real requests; isolated test directory")
        }
    }
}
