import AppKit
import WebKit

final class SurfaceCheck: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var views: [WKWebView] = []
    var finished = 0
    var opened = false
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body=message.body as? [String:Any], body["action"] as? String == "showLatest" { opened=true }
    }
    func start() {
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("apps/desktop/web")
        let logo=NSBitmapImageRep(data:try! Data(contentsOf:root.appendingPathComponent("mmemo-logo.png")))!
        assert(logo.colorAt(x:0,y:0)!.alphaComponent==0,"logo background must have zero alpha")
        assert(logo.colorAt(x:Int(Double(logo.pixelsWide)*40/625),y:Int(Double(logo.pixelsHigh)*150/185))!.alphaComponent>0.95,"lettering stays opaque")
        for (role, width, height) in [("list",376,350),("bubble",244,48)] {
            let config=WKWebViewConfiguration(); config.userContentController.add(self,name:"mmemo")
            let view=WKWebView(frame:NSRect(x:0,y:0,width:width,height:height),configuration:config)
            view.navigationDelegate=self; views.append(view)
            var url=URLComponents(url:root.appendingPathComponent("index.html"),resolvingAgainstBaseURL:false)!
            url.fragment=role; view.loadFileURL(url.url!,allowingReadAccessTo:root)
        }
        Timer.scheduledTimer(withTimeInterval:15,repeats:false) { _ in print("FAIL: timeout");exit(1) }
    }
    func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
        view.evaluateJavaScript(#"""
        (()=>{
          const el=id=>document.getElementById(id), check=(ok,msg)=>{if(!ok)throw Error(msg)};
          const visible=e=>e.getBoundingClientRect().height>0;
          const text='最新 Agent 消息\n'.repeat(30)+'<img src=x onerror=alert(1)>';
          window.mmemo.load([{id:'pending',title:'未完成',due:'',done:false},{id:'done',title:'已完成',due:'',done:true}],null);
          const group=document.querySelector('.completed-group');
          check(!group.open,'completed starts collapsed');
          check(group.querySelector('.todo').dataset.taskId==='done','completed grouping');
          check(document.querySelector('section.todo-group .todo').dataset.taskId==='pending','recent grouping');
          group.open=true;group.dispatchEvent(new Event('toggle'));window.mmemo.opened();
          check(document.querySelector('.completed-group').open,'refresh preserves expansion');
          window.mmemo.load([{id:'done',title:'已完成',due:'',done:true}],null);
          check(!document.querySelector('section.todo-group'),'empty recent group is absent');
          const promoted=el('recentHeading').querySelector('button'), completedOnly=document.querySelector('.completed-group');
          check(promoted?.textContent==='已完成 · 1' && completedOnly.querySelector('summary').hidden,'completed heading promoted without duplication');
          promoted.click();check(!completedOnly.open && promoted.getAttribute('aria-expanded')==='false','header collapses completed group');
          promoted.click();check(completedOnly.open && promoted.getAttribute('aria-expanded')==='true','header expands completed group');
          window.mmemo.latest('reply');window.mmemo.showLatest();el('latestMessage').click();
          check(!el('recentHeading').hidden && el('recentHeading').contains(promoted),'return preserves promoted heading');
          window.mmemo.load([{id:'pending',title:'未完成',due:'',done:false}],null);
          check(!document.querySelector('.completed-group'),'empty completed group is absent');
          check(el('recentHeading').textContent==='最近 · 1' && !el('recentHeading').querySelector('button'),'pending restores recent header');
          window.mmemo.load([],null);
          check(!el('list').children.length,'empty list has no groups or placeholder text');
          window.mmemo.latest('old reply');window.mmemo.latest(text);
          window.mmemo.status('大功告成了');
          check(el('bubbleText').textContent==='大功告成了','bubble displays status only');
          check(!el('bubbleText').querySelector('img'),'literal text only');
          check(!el('bubbleText').querySelector('.status-dots'),'finished message is static');
          window.mmemo.status('正在冥思苦想 ...');
          check(el('bubbleText').textContent==='正在冥思苦想 .','preserve phrase');
          check(el('bubbleText').querySelectorAll('.status-dots').length===1,'only trailing dots animate');
          window.mmemo.status('大功告成了');
          check(!el('bubbleText').querySelector('.status-dots'),'completion removes looping dots');
          check(visible(el('chatForm')) === (document.body.dataset.surface==='list'),'input belongs inside todo only');
          if(document.body.dataset.surface==='bubble'){
            check(!visible(document.querySelector('.panel')),'no todo inside bubble');
            check(el('bubbleText').getBoundingClientRect().height===20,'single static line');
            check(!el('latestMessage').disabled,'latest message remains accessible');
            el('replyBubble').click();
          }else{
            check(!visible(el('replyBubble')),'no bubble inside todo');
            if(!matchMedia('(prefers-reduced-transparency: reduce)').matches) check(getComputedStyle(document.querySelector('.panel')).backgroundColor==='rgba(237, 237, 237, 0.28)','Codex light sidebar tint');
            check(visible(el('brandLogo')) && el('brandLogo').naturalWidth>0,'brand asset loads');
            check(!el('count') && !visible(el('panelTitle')),'brand replaces heading and total');
            window.mmemo.showLatest();
            check(el('latestMessage').ariaLabel==='返回待办' && getComputedStyle(document.querySelector('.todo-line')).display!=='none','message details offer todo icon');
            check(visible(el('brandLogo')) && el('panelTitle').textContent==='消息','detail heading preserved');
            check(el('list').hidden&&!el('detail').hidden,'full message replaces entire list');
            check(el('detailText').textContent===text,'full text preserved');
            check(el('detail').scrollHeight>el('detail').clientHeight,'full message scrolls');
            window.mmemo.latest('newest');check(el('detailText').textContent==='newest','open detail follows latest');
            el('latestMessage').click();check(!el('list').hidden&&el('detail').hidden,'return restores list');
            check(visible(el('brandLogo')) && !visible(el('panelTitle')),'return restores brand');
            window.mmemo.load([{id:'pending',title:'未完成',due:'',done:false},{id:'done',title:'已完成',due:'',done:true}],null);
            check(el('recentHeading').textContent==='最近 · 1' && visible(el('recentHeading')),'first heading moves to header');
            check(!document.querySelector('section.todo-group .group-heading'),'no duplicate recent heading');
            const left=e=>e.getBoundingClientRect().left, aligned=e=>Math.abs(left(e)-left(el('chatForm')))<1;
            check(aligned(el('recentHeading')) && aligned(document.querySelector('.completed-group summary')),'group labels align with input border');
            for(const checkbox of document.querySelectorAll('.state')) check(aligned(checkbox),'checkbox aligns with input border');
            check(el('brandLogo').parentElement===el('latestMessage').parentElement && el('brandLogo').getBoundingClientRect().right<left(el('latestMessage')),'brand precedes toolbar buttons');
            check(el('brandLogo').getBoundingClientRect().height===16,'brand remains small');
            check(!el('close') && !el('back'),'close and separate back icons removed');
            check(el('latestMessage').ariaLabel==='最新消息' && getComputedStyle(document.querySelector('.todo-line')).display==='none','list offers message icon');
            window.mmemo.showLatest();el('latestMessage').click();check(el('detail').hidden,'selected message button returns to list');
          }
          return document.body.dataset.surface;
        })()
        """#) { result,error in
            if let error { print("FAIL:",error);exit(1) }
            print("PASS:",result ?? "unknown");self.finished += 1
            if self.finished==2 { guard self.opened else { print("FAIL: bubble bridge");exit(1) };self.views[0].evaluateJavaScript("document.body.style.background='#889990'") { _,error in
                if let error {print("FAIL:",error);exit(1)}
                self.views[0].takeSnapshot(with:nil) { image,error in
                    guard let image, let tiff=image.tiffRepresentation, let bitmap=NSBitmapImageRep(data:tiff) else {print("FAIL: snapshot",error as Any);exit(1)}
                    let scale=Double(bitmap.pixelsWide)/376
                    let logo=bitmap.colorAt(x:Int(248*scale),y:Int(21*scale))!.usingColorSpace(.deviceRGB)!
                    let background=bitmap.colorAt(x:Int(140*scale),y:Int(20*scale))!.usingColorSpace(.deviceRGB)!
                    assert(abs(logo.redComponent-background.redComponent)<0.03 && abs(logo.greenComponent-background.greenComponent)<0.03 && abs(logo.blueComponent-background.blueComponent)<0.03,"logo must reveal the panel background")
                    try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/tmp/mmemo-alpha-preview.png"))
                    print("PASS: logo transparency on colored background");exit(0)
                }
            } }
        }
    }
}
@main struct Main {
    static func main(){let app=NSApplication.shared;app.setActivationPolicy(.accessory);let check=SurfaceCheck();check.start();app.run()}
}
