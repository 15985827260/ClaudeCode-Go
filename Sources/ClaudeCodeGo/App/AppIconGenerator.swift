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

    static func menuBarIcon(running: Bool) -> NSImage {
        let baseName = running ? "StatusbarOn" : "StatusbarOff"
        let img = NSImage(size: NSSize(width: 32, height: 32))
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
