// Diagnostic only: inspect native tint layers, without modifying AppKit's private layers.
// Run: swift docs/qa/material-probe.swift
// Actual values vary by macOS, appearance and accessibility settings.
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSPanel(contentRect: NSRect(x: 40, y: 40, width: 380, height: 280), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
window.isOpaque = false; window.backgroundColor = .clear
window.appearance = NSAppearance(named: .aqua)
let glass = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 380, height: 280))
glass.state = .active; glass.blendingMode = .behindWindow; glass.alphaValue = 1
window.contentView = glass
window.orderFrontRegardless()
func report(_ layer: CALayer) {
    if let color = layer.backgroundColor, !layer.isHidden, layer.compositingFilter == nil {
        print("Native fill alpha:", color.alpha, "layer opacity:", layer.opacity)
    }
    if let filters = layer.filters, !filters.isEmpty { print("Native filters:", filters) }
    for child in layer.sublayers ?? [] { report(child) }
}
for (i, material) in [NSVisualEffectView.Material.underWindowBackground, .hudWindow].enumerated() {
    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i * 2)) {
        glass.material = material
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("Material:", material.rawValue)
            if let layer = glass.layer { report(layer) }
            fflush(stdout)
            if i == 1 { app.terminate(nil) }
        }
    }
}
app.run()
