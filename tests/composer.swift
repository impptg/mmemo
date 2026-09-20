import AppKit
import WebKit

final class ComposerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class ComposerCheck: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let window = ComposerWindow(contentRect: NSRect(x: 0, y: 0, width: 376, height: 432), styleMask: .borderless, backing: .buffered, defer: false)
    var web: WKWebView!
    var actions: [String] = []
    var sentText = ""
    var checkedValues: [Bool] = []
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String:Any], let action = body["action"] as? String { actions.append(action); if action == "setDone", body["id"] as? String == "a", let done = body["done"] as? Bool { checkedValues.append(done) }; if action == "undoCheckpoint" { web.undoManager?.removeAllActions() }; if action == "chat" { sentText = body["text"] as? String ?? "" } }
    }
    func start() {
        let config = WKWebViewConfiguration(); config.userContentController.add(self, name: "mmemo")
        web = WKWebView(frame: window.contentView!.bounds, configuration: config)
        window.contentView = web; web.navigationDelegate = self
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("desktop/web")
        var url = URLComponents(url: root.appendingPathComponent("index.html"), resolvingAgainstBaseURL: false)!
        url.fragment = "list"
        web.loadFileURL(url.url!, allowingReadAccessTo: root)
        Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in print("FAIL: WebKit check timed out"); exit(1) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        window.makeFirstResponder(web)
        web.callAsyncJavaScript(#"""
        return await (async () => {
          await new Promise(resolve=>setTimeout(resolve,100));
          const input=document.getElementById('chatInput');
          const height=()=>input.getBoundingClientRect().height;
          const check=(ok,label)=>{if(!ok)throw Error(label)};
          const type=value=>{input.textContent=value;input.dispatchEvent(new Event('input'))};
          check(input.isContentEditable,'rich token editor');
          input.focus();
          check(getComputedStyle(input).outlineStyle==='none','focused editor has no inner black frame');
          check(getComputedStyle(input,'::before').content==='none','focused editor hides placeholder: '+getComputedStyle(input,'::before').content+' focused='+input.matches(':focus'));
          input.textContent='测试';input.append(document.createElement('br'));input.dispatchEvent(new Event('input'));input.blur();
          check(getComputedStyle(input,'::before').content==='none','text plus trailing br never shows placeholder');
          type('');check(getComputedStyle(input,'::before').content!=='none','empty blurred editor shows placeholder');
          check(!document.getElementById('aiStatus'),'status label should be removed');
          check(height()===24,'initial single line');
          type('first\nsecond'); check(height()===48,'grows to two lines');
          type('first\nsecond\nthird\nfourth'); check(height()===72 && input.scrollHeight>72,'caps at three lines and scrolls');
          type('a long message '.repeat(40)); check(height()===72,'wrapped text caps at three lines');
          type(''); check(height()===24,'clearing collapses');
          type('first\nsecond'); window.mmemo.replied(null,null,'failed'); check(input.textContent==='first\nsecond' && height()===48,'failure retains draft');
          window.mmemo.replied('done',[],null); check(input.textContent==='' && height()===24,'success clears and collapses');
          check(!document.getElementById('statusFooter'),'no execution footer');
          const button=document.getElementById('sendButton');
          const centered=()=>{
            const outer=button.getBoundingClientRect(), icon=button.querySelector('svg').getBoundingClientRect();
            check(Math.abs(outer.x+outer.width/2-icon.x-icon.width/2)<0.1 && Math.abs(outer.y+outer.height/2-icon.y-icon.height/2)<0.1,'icon centered in circle: '+JSON.stringify({outer:outer.toJSON(),icon:icon.toJSON(),padding:getComputedStyle(button).padding}));
          };
          centered();
          check(button.disabled,'empty input disables send');
          const tasks=[{id:'a',title:'相同标题超过五字',done:false,due:''},{id:'b',title:'相同标题超过五字',done:false,due:''}];
          window.mmemo.load(tasks,null);
          const checkbox=()=>document.querySelector('.todo[data-task-id="a"] .state');
          checkbox().click();
          check(!input.querySelector('.task-token') && input.textContent==='','checkbox never inserts a token');
          check(checkbox().getAttribute('aria-checked')==='false','checkbox waits for successful save');
          window.mmemo.load([{...tasks[0],done:true},tasks[1]],null);
          check(checkbox().getAttribute('aria-checked')==='true','saved completion appears checked');
          checkbox().click();check(!input.querySelector('.task-token'),'unchecking does not select a token');
          window.mmemo.load(tasks,null);
          const rows=()=>document.querySelectorAll('.todo');
          const tokens=()=>input.querySelectorAll('.task-token');
          const choose=async(i,multiple=false)=>{rows()[i].focus();rows()[i].dispatchEvent(new MouseEvent('click',{bubbles:true,metaKey:multiple}));await new Promise(resolve=>setTimeout(resolve,30));};
          await choose(0);check(tokens().length===1 && tokens()[0].dataset.taskId==='a','single selection inserts token');
          check(tokens()[0].textContent==='相同标题超...','token shows five characters and ellipsis');
          check(getComputedStyle(tokens()[0]).display==='inline' && getComputedStyle(tokens()[0]).lineHeight===getComputedStyle(input).lineHeight && getComputedStyle(tokens()[0]).verticalAlign==='baseline','token shares text line metrics for a stable caret');
          check(tokens()[0].title==='相同标题超过五字' && composerText().includes('相同标题超过五字'),'full title survives display truncation');
          check(getComputedStyle(tokens()[0]).backgroundColor==='rgb(220, 242, 225)','token uses light green');
          await choose(1,true);
          check(tokens().length===2 && [...tokens()].every(t=>getComputedStyle(t).webkitUserModify==='read-only'),'cmd selection adds atomic tokens: '+input.innerHTML);
          check(composerText().includes('todo:a') && composerText().includes('todo:b'),'same-title references keep distinct IDs');
          const start=document.createRange();start.selectNodeContents(input);start.collapse(true);getSelection().removeAllRanges();getSelection().addRange(start);
          input.click();
          const remainder=document.createRange();remainder.selectNodeContents(input);remainder.setStart(getSelection().anchorNode,getSelection().anchorOffset);
          check(remainder.toString()==='','clicking token-only draft places caret after all tokens');
          document.execCommand('insertText',false,'改到明天');
          check(composerText().trim().endsWith('改到明天') && tokens().length===2,'typing follows both atomic tokens');
          document.execCommand('delete');
          type('');await choose(0);await choose(1,true);

          await choose(0,true);check(tokens().length===1 && tokens()[0].dataset.taskId==='b','cmd click toggles');
          await choose(0);check(tokens().length===1 && tokens()[0].dataset.taskId==='a','plain click replaces selection');
          check(height()===24,'reselecting tokens does not add blank lines '+height()+': '+input.innerHTML);
          window.webkit.messageHandlers.mmemo.postMessage({action:'undoCheckpoint'});await new Promise(resolve=>setTimeout(resolve,100));
          const range=document.createRange();range.setStartAfter(tokens()[0]);range.collapse(true);getSelection().removeAllRanges();getSelection().addRange(range);
          document.execCommand('delete');check(tokens().length===0,'token deletes as a whole');
          await new Promise(resolve=>setTimeout(resolve,30));document.execCommand('undo');check(tokens().length===1,'native undo restores token: '+input.innerHTML);
          window.mmemo.replied(null,null,'failed');check(tokens().length===1,'failure retains references');
          window.mmemo.replied('done',[],null);check(tokens().length===0 && button.disabled,'success clears references and disables send');
          type('汉'.repeat(40));
          const textNode=input.firstChild, bounds=input.getBoundingClientRect(), send=button.getBoundingClientRect();
          let fullWidth=false;
          for(let i=0;i<textNode.length;i++){const r=document.createRange();r.setStart(textNode,i);r.setEnd(textNode,i+1);const rect=r.getBoundingClientRect();if(rect.top<bounds.top+24 && rect.right>send.left)fullWidth=true;}
          check(fullWidth,'first line uses width above send button');
          const tail=getComputedStyle(input,'::after');check(parseFloat(tail.width)>=32,'last line reserves send button space');
          window.mmemo.configure('test');window.mmemo.load(tasks,null); type('test request');await choose(0); button.click();
          check(button.ariaLabel==='停止任务' && !button.disabled && !input.isContentEditable,'sending enables stop');
          centered();
          button.click(); window.mmemo.stopped();
          check(button.ariaLabel==='发送' && input.isContentEditable && input.textContent.includes('test request') && tokens().length===1,'stop restores draft');
          check((window.mmemo.showLatest(), document.getElementById('detailText').textContent==='done'),'user input and cancellation never replace latest agent message');
          window.mmemo.replied(null,null,'network error');
          check((window.mmemo.showLatest(), document.getElementById('detailText').textContent==='done'),'errors never replace latest agent message');
          window.mmemo.replied('new agent reply',[],null);
          check((window.mmemo.showLatest(), document.getElementById('detailText').textContent==='new agent reply'),'new reply replaces, never appends');
          return 'PASS: atomic references, Cmd selection, deletion/undo, native payload IDs, full-width wrapping, draft recovery and send/stop';
        })()
        """#, arguments: [:], in: nil, in: .page) { outcome in
            guard case .success(let result) = outcome else { print("FAIL:", outcome); exit(1) }
            guard self.actions.contains("chat"), self.actions.contains("stop") else { print("FAIL: missing chat/stop bridge action"); exit(1) }
            guard self.sentText.contains("todo:a"), self.sentText.contains("test request") else { print("FAIL: reference ID missing from native chat"); exit(1) }
            guard self.checkedValues == [true, false] else { print("FAIL: checkbox bridge values", self.checkedValues); exit(1) }
            print(result); exit(0)
        }
    }
}
@main struct Main {
    static func main() {
        let app=NSApplication.shared; app.setActivationPolicy(.accessory)
        let check=ComposerCheck(); check.start(); app.run()
    }
}
