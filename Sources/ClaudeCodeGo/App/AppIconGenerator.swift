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
    /// Loads a multi-representation NSImage with @1x (32×32) and @2x (64×64)
    /// so macOS picks the right size for the current display.
    static func menuBarIcon(running: Bool) -> NSImage {
        let baseName = running ? "StatusbarOn" : "StatusbarOff"
        let img = NSImage(size: NSSize(width: 32, height: 32))

        for (suffix, scale) in [("", NSSize(width: 32, height: 32)), ("@2x", NSSize(width: 64, height: 64))] {
            let name = baseName + suffix
            if let path = Bundle.module.path(forResource: name, ofType: "png"),
               let nsImage = NSImage(contentsOfFile: path),
               let rep = nsImage.representations.first {
                rep.size = scale
                img.addRepresentation(rep)
            }
        }

        // Fallback: try single PNG
        if img.representations.isEmpty,
           let path = Bundle.module.path(forResource: baseName, ofType: "png"),
           let single = NSImage(contentsOfFile: path) {
            return single
        }

        img.isTemplate = true
        return img
    }
}
