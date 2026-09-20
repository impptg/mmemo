let app=NSApplication.shared
let delegate=AppDelegate();app.delegate=delegate
Timer.scheduledTimer(withTimeInterval:1,repeats:false){ _ in
 delegate.responding=true;delegate.startBubble()
 delegate.bubbleWeb.callAsyncJavaScript("""
 const rows=[];
 for(let i=0;i<6;i++) {await new Promise(r=>setTimeout(r,450));const b=document.getElementById('bubbleText');const d=document.querySelector('.status-dots');rows.push({text:b.textContent,width:b.clientWidth,needed:b.scrollWidth,dotsRight:d.getBoundingClientRect().right,labelRight:b.getBoundingClientRect().right});}
 if(rows.some(r=>r.needed>r.width || r.dotsRight>r.labelRight+0.1)) throw Error('Dots clipped');
 if(new Set(rows.map(r=>r.text)).size!==3) throw Error('Not cycling');
 return rows;
 """,arguments:[:],in:nil,in:.page){r in switch r {case .success(let v):print(v);exit(0);case .failure(let e):print(e);exit(1)}}
}
app.run()
