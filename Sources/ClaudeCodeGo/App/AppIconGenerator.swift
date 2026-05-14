import AppKit

/// Loads the app icon from the asset catalog.
enum AppIconGenerator {
    static func setAppIcon() {
        // Try asset catalog first (Xcode project), fall back to bundled PNG (SPM)
        if let image = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = image
        } else if let path = Bundle.module.path(forResource: "AppIcon", ofType: "png"),
                  let image = NSImage(contentsOfFile: path) {
            NSApp.applicationIconImage = image
        }
    }

    /// Returns the menu bar icon for the given state.
    static func menuBarIcon(running: Bool) -> NSImage {
        let name = running ? "MenubarOn" : "MenubarOff"
        if let image = NSImage(named: name) {
            return image
        }
        // Fallback: load from bundled resource
        if let path = Bundle.module.path(forResource: name, ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            return image
        }
        // Last resort: small colored dot
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(running
                ? CGColor(srgbRed: 0.3, green: 0.69, blue: 0.52, alpha: 1)
                : CGColor(srgbRed: 0.78, green: 0.8, blue: 0.85, alpha: 1))
            ctx.fillEllipse(in: rect)
            return true
        }
        return img
    }
}
