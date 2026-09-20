import AppKit
let folder=URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
for (name,symbol) in [("check","checkmark"),("send","arrow.up"),("close","xmark"),("filter","line.3.horizontal.decrease")] {
    let icon=NSImage(systemSymbolName:symbol,accessibilityDescription:nil)!.withSymbolConfiguration(.init(pointSize:24,weight:.medium))!
    let image=NSImage(size:NSSize(width:48,height:48))
    image.lockFocus()
    (["check", "send"].contains(name) ? NSColor.white : NSColor.darkGray).set()
    let ratio=min(38/icon.size.width,38/icon.size.height)
    let size=NSSize(width:icon.size.width*ratio,height:icon.size.height*ratio)
    icon.draw(in:NSRect(x:(48-size.width)/2,y:(48-size.height)/2,width:size.width,height:size.height))
    NSRect(x:0,y:0,width:48,height:48).fill(using:.sourceAtop)
    image.unlockFocus()
    let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
    try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name+".png"))
}
