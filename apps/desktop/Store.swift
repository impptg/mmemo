import Foundation

/// A typed composer snapshot; never persist or restore executable HTML.
enum ComposerDraft {
    static func checked(_ value: Any) throws -> [String: Any] {
        guard let draft = value as? [String: Any], draft["version"] as? Int == 1,
              let parts = draft["parts"] as? [[String: String]], parts.count <= 4096 else {
            throw NSError(domain: "mmemo.draft", code: 1)
        }
        var count = 0
        for part in parts {
            switch part["kind"] {
            case "text":
                guard let text = part["text"], Set(part.keys) == ["kind", "text"] else { throw NSError(domain: "mmemo.draft", code: 2) }
                count += text.utf8.count
            case "task":
                guard let id = part["id"], !id.isEmpty, id.count <= 100,
                      let title = part["title"], title.count <= 200,
                      Set(part.keys) == ["kind", "id", "title"] else { throw NSError(domain: "mmemo.draft", code: 3) }
                count += id.utf8.count + title.utf8.count
            default: throw NSError(domain: "mmemo.draft", code: 4)
            }
        }
        guard count <= 131072 else { throw NSError(domain: "mmemo.draft", code: 5) }
        return ["version": 1, "parts": parts]
    }

    static func save(_ value: Any, directory: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: checked(value), options: [.sortedKeys])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("composer-draft.json")
        if (try? Data(contentsOf: file)) == data { return }
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    static func load(directory: URL) throws -> [String: Any] {
        let file = directory.appendingPathComponent("composer-draft.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return ["version": 1, "parts": [[String: String]]()] }
        return try checked(JSONSerialization.jsonObject(with: Data(contentsOf: file)))
    }
}

struct CloudAccount: Codable, Equatable {
    let username: String
    let uid: String
    let avatar: String
    static let all = [
        CloudAccount(username:"user_pptg",uid:"2100541450115510274",avatar:"frog"),
        CloudAccount(username:"user_mm",uid:"2100541456125558785",avatar:"raccoon")
    ]
}


struct Todo: Codable, Equatable {
    let id: String
    let title: String
    let due: String
    let done: Bool
    var member: String? = nil
    var createdBy: String? = nil
    var participants: [String]? = nil
}

struct TaskStore {
    let directory: URL
    var file: URL { directory.appendingPathComponent("todos.json") }

    func load() throws -> [Todo] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let tasks = try JSONDecoder().decode([Todo].self, from: Data(contentsOf: file))
        try validate(tasks)
        return tasks
    }

    func validate(_ tasks: [Todo]) throws {
        guard tasks.count <= 10000, Set(tasks.map(\.id)).count == tasks.count,
              tasks.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 100 && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 200 && $0.due.count <= 16 && ($0.member == nil || $0.member == "me" || $0.member == "partner") }) else {
            throw NSError(domain: "mmemo", code: 1, userInfo: [NSLocalizedDescriptionKey: "待办数据格式不正确"])
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.isLenient = false
        let memberIDs=Set(CloudAccount.all.map(\.uid))
        for task in tasks {
            if let ids=task.participants {
                guard (1...2).contains(ids.count),Set(ids).count==ids.count,Set(ids).isSubset(of:memberIDs) else {throw NSError(domain:"mmemo",code:6,userInfo:[NSLocalizedDescriptionKey:"参与人不正确"])}
            }
        }
        for task in tasks where !task.due.isEmpty {
            guard task.due.count == 16, let date = formatter.date(from: task.due), formatter.string(from: date) == task.due else {
                throw NSError(domain: "mmemo", code: 4, userInfo: [NSLocalizedDescriptionKey: "待办日期不正确"])
            }
        }
    }

    func save(_ tasks: [Todo]) throws {
        try validate(tasks)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tasks)
        if FileManager.default.fileExists(atPath: file.path) {
            let previous = try Data(contentsOf: file)
            let existing = try JSONDecoder().decode([Todo].self, from: previous)
            try validate(existing)
            try previous.write(to: directory.appendingPathComponent("todos.backup.json"), options: .atomic)
        }
        try data.write(to: file, options: .atomic)
    }

    func setDone(id: String, done: Bool) throws {
        var tasks = try load()
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            throw NSError(domain: "mmemo", code: 5, userInfo: [NSLocalizedDescriptionKey: "事项已不存在，请刷新后重试"])
        }
        let task = tasks[index]
        tasks[index] = Todo(id: task.id, title: task.title, due: task.due, done: done, member: task.member, createdBy: task.createdBy, participants: task.participants)
        try save(tasks)
    }
}

struct HeartNotificationState: Codable {
    var startedAt: Date?
    var boosts = 0
    var dueSeen: [String:String] = [:]
    var received: [String] = []

    func level(at now: Date = Date()) -> Int {
        guard let startedAt else {return 0}
        return min(10, boosts + Int(min(10, max(0, now.timeIntervalSince(startedAt) / 120))))
    }
    mutating func increase(_ count: Int, at now: Date) {
        guard count > 0 else {return}
        if startedAt == nil {startedAt=now}
        boosts=min(10,boosts+count)
    }
    mutating func receive(_ ids: [String], at now: Date = Date()) {
        let fresh=Set(ids).subtracting(received)
        increase(fresh.count,at:now)
        received=Array((received+fresh.sorted()).suffix(200))
    }
    mutating func refresh(_ tasks: [Todo], at now: Date = Date()) {
        let format=DateFormatter();format.locale=Locale(identifier:"en_US_POSIX");format.dateFormat="yyyy-MM-dd'T'HH:mm"
        let due=tasks.filter {!$0.done && (format.date(from:$0.due).map {$0<=now} ?? false)}
        let current=Dictionary(uniqueKeysWithValues:due.map {($0.id,$0.due)})
        if current.contains(where:{dueSeen[$0.key] != $0.value}) {increase(1,at:now)}
        dueSeen=current
    }
    mutating func viewed() {startedAt=nil;boosts=0}
}
