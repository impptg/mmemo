import AppKit
import WebKit
final class Check: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
var web: WKWebView!
let window=NSWindow(contentRect:NSRect(x:400,y:400,width:256,height:62),styleMask:.borderless,backing:.buffered,defer:false)
func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage){}
func start(){let c=WKWebViewConfiguration();c.userContentController.add(self,name:"mmemo");web=WKWebView(frame:window.contentView!.bounds,configuration:c);web.navigationDelegate=self;window.contentView=web;window.orderFrontRegardless();let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("desktop/web");web.loadFileURL(URL(string:root.appendingPathComponent("index.html").absoluteString+"#bubble")!,allowingReadAccessTo:root)}
func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){web.callAsyncJavaScript("""
window.mmemo.status('正在冥思苦想 ...');
const d=document.querySelector('.status-dots');const values=[];
for(let i=0;i<9;i++){await new Promise(r=>setTimeout(r,220));values.push({width:d.getBoundingClientRect().width,animation:getComputedStyle(d).animationName, text:d.textContent});}
const seen=new Set(values.map(v=>v.text));
if(!['.','..','...'].every(v=>seen.has(v))) throw Error('Missing dot phase');
window.mmemo.status('大功告成了');
await new Promise(r=>setTimeout(r,500));
if(document.querySelector('#bubbleText').textContent!=='大功告成了') throw Error('Completion still animates');
return {passed:true,values};
""",arguments:[:],in:nil,in:.page){result in switch result { case .success(let value): print(value ?? "PASS"); exit(0); case .failure(let error): print("FAIL:",error); exit(1) }}}
}
@main struct Main{static func main(){let app=NSApplication.shared;app.setActivationPolicy(.accessory);let c=Check();c.start();app.run()}}
