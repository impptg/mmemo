import Foundation

struct CloudConfiguration: Codable {
    let baseURL: String
    let username: String
    let password: String
    let uid: String
    let deviceId: String
    var account: CloudAccount? { CloudAccount.all.first { $0.uid == uid && $0.username == username } }
    static func load(directory: URL) throws -> Self {
        let config=try JSONDecoder().decode(Self.self,from:Data(contentsOf:directory.appendingPathComponent("server.json")))
        guard URL(string:config.baseURL)?.scheme == "https", config.account != nil, !config.password.isEmpty, UUID(uuidString:config.deviceId) != nil else { throw AIError("云端账号配置不正确") }
        return config
    }
}

private struct CloudToken: Codable {
    let access_token: String
    let refresh_token: String
    let expires_in: Double
    let sub: String
}
private struct CloudSession: Codable {
    let token: CloudToken
    let expiresAt: Date
}
private struct CloudRow: Decodable {
    let id: String
    let title: String
    let due: String
    let done: Bool
    let created_by: String
    let participants: [String]
    var todo: Todo { Todo(id:id,title:title,due:due,done:done,createdBy:created_by,participants:participants) }
}

@MainActor final class CloudClient {
    let config: CloudConfiguration
    let directory: URL
    private let network: URLSession
    private let streaming: URLSession
    private var watchTask: Task<Void,Never>?
    private var session: CloudSession?
    private var authentication: Task<CloudToken,Error>?
    private var base: String { config.baseURL }

    init(config: CloudConfiguration, directory: URL) {
        self.config=config;self.directory=directory
        let settings=URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest=20;settings.timeoutIntervalForResource=30
        network=URLSession(configuration:settings)
        let streamSettings=URLSessionConfiguration.ephemeral
        streamSettings.timeoutIntervalForRequest=45;streamSettings.timeoutIntervalForResource=86400
        streaming=URLSession(configuration:streamSettings)
        if let data=try? Data(contentsOf:directory.appendingPathComponent("server-session.json")), let saved=try? JSONDecoder().decode(CloudSession.self,from:data), saved.token.sub==config.uid {session=saved}
    }
    private func send(_ path: String, body: [String:Any]? = nil, token: String? = nil, requestID: String? = nil) async throws -> Data {
        guard let url=URL(string:base+path) else {throw AIError("云端地址不正确")}
        var request=URLRequest(url:url);request.httpMethod=body == nil ? "GET" : "POST"
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue(config.deviceId,forHTTPHeaderField:"x-device-id")
        if let requestID {request.setValue(requestID,forHTTPHeaderField:"Idempotency-Key")}
        if let token {request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")}
        if let body {request.httpBody=try JSONSerialization.data(withJSONObject:body)}
        let (data,response)=try await network.data(for:request)
        guard let http=response as? HTTPURLResponse else {throw AIError("云端响应不正确")}
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode==401 {session=nil}
            throw AIError(http.statusCode==401 ? "云端登录已失效，请稍后重试" : "云端请求失败（\(http.statusCode)），请刷新检查")
        }
        return data
    }
    private func accessToken() async throws -> String {
        if let session, session.expiresAt.timeIntervalSinceNow>60 {return session.token.access_token}
        let task: Task<CloudToken,Error>
        if let authentication {task=authentication}
        else {
            task=Task {
                if let old=session {
                    do {
                        let data=try await send("/auth/refresh",body:["refresh_token":old.token.refresh_token])
                        return try JSONDecoder().decode(CloudToken.self,from:data)
                    } catch { if Task.isCancelled {throw CancellationError()} }
                }
                let data=try await send("/auth/login",body:["username":config.username,"password":config.password])
                return try JSONDecoder().decode(CloudToken.self,from:data)
            }
            authentication=task
        }
        defer {authentication=nil}
        let token=try await task.value
        guard token.sub==config.uid, !token.access_token.isEmpty else {throw AIError("云端登录身份与本地账号不一致")}
        let saved=CloudSession(token:token,expiresAt:Date().addingTimeInterval(token.expires_in))
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try JSONEncoder().encode(saved).write(to:directory.appendingPathComponent("server-session.json"),options:[.atomic,.completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:directory.appendingPathComponent("server-session.json").path)
        session=saved
        return token.access_token
    }
    func fetch() async throws -> [Todo] {
        let token=try await accessToken()
        let data=try await send("/v1/todos",token:token)
        let tasks=try JSONDecoder().decode([CloudRow].self,from:data).map(\.todo)
        try TaskStore(directory:directory).validate(tasks)
        return tasks
    }
    func apply(_ changes:[[String:Any]]) async throws {
        let token=try await accessToken()
        // Reuse one key across transport retries; the server commits each mutation once.
        do {try await mutate("/v1/todos/apply",body:["changes":changes],token:token)}
        catch {throw AIError("云端操作未确认，请先刷新核对，避免重复提交。")}
    }
    func sendHeart() async throws {
        let token=try await accessToken()
        try await mutate("/v1/hearts/send",body:[:],token:token)
    }
    func fetchHearts() async throws -> [String] {
        struct Heart: Decodable { let id: String }
        let token=try await accessToken()
        let data=try await send("/v1/hearts",token:token)
        return try JSONDecoder().decode([Heart].self,from:data).map(\.id)
    }
    func ackHearts(_ ids: [String]) async throws {
        let token=try await accessToken()
        _ = try await send("/v1/hearts/ack",body:["ids":ids],token:token)
    }
    private func mutate(_ path:String,body:[String:Any],token:String) async throws {
        let key=UUID().uuidString
        do {_ = try await send(path,body:body,token:token,requestID:key)}
        catch let error as URLError {
            guard !Task.isCancelled else {throw CancellationError()}
            if [.timedOut,.networkConnectionLost,.cannotConnectToHost].contains(error.code) {
                _ = try await send(path,body:body,token:token,requestID:key)
            } else {throw error}
        }
    }
    func stopWatching() {watchTask?.cancel();watchTask=nil}
    func watch(onChange:@escaping @MainActor ()->Void,onDisconnect:@escaping @MainActor ()->Void) {
        stopWatching()
        watchTask=Task { [weak self] in
            guard let self else {return}
            var delay:UInt64=1
            while !Task.isCancelled {
                do {
                    let token=try await self.accessToken()
                    var request=URLRequest(url:URL(string:self.base+"/v1/events")!)
                    request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
                    request.setValue("text/event-stream",forHTTPHeaderField:"Accept")
                    let (bytes,response)=try await self.streaming.bytes(for:request)
                    guard (response as? HTTPURLResponse)?.statusCode==200 else {
                        if (response as? HTTPURLResponse)?.statusCode==401 {self.session=nil}
                        throw AIError("实时连接暂不可用")
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if line.hasPrefix("data:") {delay=1;onChange()}
                    }
                } catch {if Task.isCancelled {return}}
                if Task.isCancelled {return}
                onDisconnect()
                try? await Task.sleep(nanoseconds:delay*1_000_000_000)
                delay=min(delay*2,30)
            }
        }
    }
    static func changes(before:[Todo], after:[Todo]) -> [[String:Any]] {
        let old=Dictionary(uniqueKeysWithValues:before.map {($0.id,$0)})
        let ids=Set(after.map(\.id))
        var changes:[[String:Any]]=[]
        for task in after {
            if let previous=old[task.id] {
                var patch:[String:Any]=[:]
                if previous.title != task.title {patch["title"]=task.title}
                if previous.due != task.due {patch["due"]=task.due}
                if previous.done != task.done {patch["done"]=task.done}
                if previous.participants != task.participants, let ids=task.participants {patch["participants"]=ids}
                if !patch.isEmpty {changes.append(["action":"update","id":task.id,"patch":patch])}
            } else {
                var patch:[String:Any]=["title":task.title,"due":task.due,"done":task.done]
                if let ids=task.participants {patch["participants"]=ids}
                changes.append(["action":"create","id":task.id,"patch":patch])
            }
        }
        for task in before where !ids.contains(task.id) {changes.append(["action":"delete","id":task.id])}
        return changes
    }
}
