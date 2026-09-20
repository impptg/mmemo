import Foundation

@main struct CloudCheck {
    @MainActor static func main() async throws {
        let base=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/mmemo/development")
        func client(_ name:String) throws -> CloudClient {
            let directory=base.appendingPathComponent(name)
            return CloudClient(config:try CloudConfiguration.load(directory:directory),directory:directory)
        }
        let a=try client("user_pptg"), b=try client("user_mm")
        let id="sync-check-"+UUID().uuidString, second="sync-check-"+UUID().uuidString
        let old=Todo(id:id,title:"before",due:"",done:false,createdBy:a.config.uid)
        let changed=Todo(id:id,title:"after",due:"",done:false,createdBy:a.config.uid)
        let patch=CloudClient.changes(before:[old],after:[changed])[0]["patch"] as! [String:Any]
        assert(patch.count==1 && patch["title"] as? String=="after","only changed fields are sent")
        let originalA=try await a.fetch(), originalB=try await b.fetch()
        assert(originalA==originalB,"both users share cloud rows")
        var created=[String]()
        do {
            try await a.apply([["action":"create","id":id,"patch":["title":"双端验证 A","due":"","done":false,"participants":[a.config.uid,b.config.uid]]]]);created.append(id)
            let fromB=try await b.fetch()
            assert(fromB.first(where:{$0.id==id})?.createdBy==a.config.uid,"A identity survives B reading")
            try await b.apply([["action":"update","id":id,"patch":["done":true]]])
            let completed=try await a.fetch()
            assert(completed.first(where:{$0.id==id})?.done==true)
            assert(completed.first(where:{$0.id==id})?.participants==[a.config.uid,b.config.uid])
            try await a.apply([["action":"update","id":id,"patch":["done":false]]])
            let reopened=try await b.fetch();assert(reopened.first(where:{$0.id==id})?.done==false)
            for invalid in [[],[a.config.uid,a.config.uid],["outsider"]] as [[String]] {
                do {
                    try await a.apply([["action":"update","id":id,"patch":["participants":invalid]]])
                    fatalError("invalid participants must fail")
                } catch {}
            }
            try await a.apply([["action":"update","id":id,"patch":["participants":[b.config.uid]]]])
            let assigned=try await b.fetch();assert(assigned.first(where:{$0.id==id})?.participants==[b.config.uid])
            assert(completed.first(where:{$0.id==id})?.createdBy==a.config.uid,"B editing does not steal A avatar")
            try await b.apply([["action":"create","id":second,"patch":["title":"双端验证 B","due":"","done":false]]]);created.append(second)
            let bCreated=try await a.fetch()
            assert(bCreated.first(where:{$0.id==second})?.createdBy==b.config.uid)
            do {
                try await a.apply([["action":"update","id":id,"patch":["title":"must rollback"]],["action":"update","id":"missing-"+UUID().uuidString,"patch":["done":false]]])
                fatalError("invalid batch must fail")
            } catch {}
            let rollback=try await b.fetch()
            assert(rollback.first(where:{$0.id==id})?.title=="双端验证 A","batch is atomic")
            do {
                try await b.apply([["action":"update","id":id,"patch":["created_by":b.config.uid]]])
                fatalError("forged creator must fail")
            } catch {}
            try await a.apply([["action":"update","id":second,"patch":["title":"反向更新"]]])
            let reverse=try await b.fetch();assert(reverse.first(where:{$0.id==second})?.title=="反向更新")
            try await b.apply(created.map {["action":"delete","id":$0]});created=[]
            let finalA=try await a.fetch(), finalB=try await b.fetch()
            assert(!finalA.contains(where:{$0.id==id || $0.id==second}) && finalA==finalB)
            print("PASS: real A/B login, shared CRUD, participants validation/reassignment, either member completion, fixed creator, rollback, forged creator rejection, cleanup")
        } catch {
            if !created.isEmpty {try? await a.apply(created.map {["action":"delete","id":$0]})}
            throw error
        }
    }
}
