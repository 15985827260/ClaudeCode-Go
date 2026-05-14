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

    /// Returns a small template image for the menu bar icon.
    static func menuBarIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(CGColor(srgbRed: 0.25, green: 0.25, blue: 0.25, alpha: 1))
            ctx.fillEllipse(in: rect.insetBy(dx: 1, dy: 1))

            let text = "CG" as NSString
            let font = NSFont.systemFont(ofSize: 11, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
            let textSize = text.size(withAttributes: attrs)
            text.draw(in: CGRect(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2 - 1,
                width: textSize.width,
                height: textSize.height
            ), withAttributes: attrs)
            return true
        }
        img.isTemplate = true
        return img
    }
}
