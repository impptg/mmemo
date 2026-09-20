#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d /tmp/mmemo-native-check.XXXXXX)
# Exercise the real AppDelegate with a separate preferences domain and no model calls.
python3 - "$work/main.swift" <<'PY'
import sys
source=open('desktop/main.swift').read().split('let app=NSApplication.shared')[0]
source=source.replace('let resources = Bundle.main.resourceURL!.absoluteURL', 'let resources = URL(fileURLWithPath: CommandLine.arguments[1])')
open(sys.argv[1],'w').write(source + r'''
let app=NSApplication.shared
let delegate=AppDelegate()
app.delegate=delegate
var attempts=0
Timer.scheduledTimer(withTimeInterval:0.2,repeats:true) { timer in
    attempts += 1
    guard delegate.readyWebs.count == 2 else {
        if attempts>75 { print("FAIL: two surfaces did not load");exit(1) }
        return
    }
    timer.invalidate()
    let panels=[delegate.panel!,delegate.bubblePanel!]
    let glass = delegate.panel.contentView!.subviews.compactMap { $0 as? NSVisualEffectView }.first!
    assert(glass.material == .menu && glass.blendingMode == .behindWindow && glass.state == .active)
    assert(!delegate.panel.isOpaque && delegate.panel.backgroundColor!.alphaComponent == 0)
    assert(Set(panels.map { $0.windowNumber }).count==2)
    assert(!delegate.bubblePanel.isVisible)
    delegate.showPanels()
    assert(!delegate.bubblePanel.isVisible)
    delegate.hide()
    assert(abs(delegate.bubblePanel.frame.maxX - delegate.frog.frame.minX)<0.1)
    assert(!delegate.bubblePanel.frame.intersects(delegate.frog.frame))
    assert(!delegate.bubblePanel.frame.insetBy(dx:8,dy:8).intersects(delegate.panel.frame.insetBy(dx:8,dy:8)))
    assert(abs(delegate.panel.frame.maxX - 28 - delegate.frog.frame.minX)<0.1)
    assert(abs(delegate.panel.frame.maxY - 28 - delegate.frog.frame.minY)<0.1)
    let original = delegate.frog.frame.origin
    let screen = delegate.frog.screen!.visibleFrame
    delegate.frog.setFrameOrigin(NSPoint(x:original.x,y:screen.minY+4))
    delegate.positionPanel()
    assert(abs(delegate.panel.frame.minY + 28 - delegate.frog.frame.maxY)<0.1)
    assert(!delegate.bubblePanel.frame.intersects(delegate.frog.frame))
    delegate.frog.setFrameOrigin(original)
    delegate.positionPanel()
    delegate.updateBubble("好")
    let shortWidth = delegate.bubblePanel.frame.width
    delegate.updateBubble("这次没成功，点我看看")
    assert(delegate.bubblePanel.frame.width > shortWidth + 70)
    delegate.updateBubble("好")
    assert(delegate.bubblePanel.frame.width == shortWidth)
    delegate.latestReply="Native bridge check: latest agent message"
    delegate.call("window.mmemo.latest(text)",args:["text":delegate.latestReply!])
    delegate.bubbleWeb.evaluateJavaScript("document.getElementById('replyBubble').click()") { _,error in
        if let error { print("FAIL:",error);exit(1) }
        Timer.scheduledTimer(withTimeInterval:0.3,repeats:false) { _ in
            assert(delegate.panel.isVisible)
            delegate.web.evaluateJavaScript("!document.getElementById('detail').hidden && document.getElementById('detailText').textContent === 'Native bridge check: latest agent message'") { result,error in
                assert(error==nil && result as? Bool == true)
                delegate.responding=true
                delegate.startBubble()
                assert(delegate.bubblePanel.isVisible && delegate.bubblePanel.parent === delegate.frog)
                assert(delegate.bubblePhrase=="有点晕碳 ...")
                assert(delegate.bubbleTimer!.timeInterval==5)
                delegate.bubbleTimer?.fire()
                assert(delegate.bubblePhrase=="小脑袋转转转 ...")
                delegate.bubbleTimer?.fire()
                assert(delegate.bubblePhrase=="正在冥思苦想 ...")
                delegate.bubbleTimer?.fire()
                assert(delegate.bubblePhrase=="有点晕碳 ...")
                delegate.responding=false
                delegate.finishBubble("大功告成了")
                assert(delegate.bubbleDeadline!.timeIntervalSinceNow > 5.8 && delegate.bubbleDeadline!.timeIntervalSinceNow <= 6)
                delegate.hoverBubble(true)
                assert(delegate.bubbleDeadline==nil && !delegate.bubbleTimer!.isValid)
                delegate.hoverBubble(false)
                assert(delegate.bubbleTimer!.isValid)
                let oldTimer=delegate.bubbleTimer!
                delegate.startBubble()
                assert(!oldTimer.isValid && delegate.bubbleDeadline==nil)
                delegate.finishBubble("大功告成了")
                delegate.bubbleTimer?.fire()
                assert(!delegate.bubblePanel.isVisible)
                assert(delegate.latestReply != nil)
                delegate.hide()
                assert(!delegate.panel.isVisible)
                print("PASS: content-sized speech bubble beside frog, separated list, bubble click bridge, full message and hide")
                exit(0)
            }
        }
    }
}
app.run()
''')
PY
swiftc desktop/Store.swift desktop/AI.swift desktop/Cloud.swift "$work/main.swift" -o "$work/mmemo-native-check" -framework AppKit -framework WebKit
"$work/mmemo-native-check" "$PWD/dist/mmemo.app/Contents/Resources"
