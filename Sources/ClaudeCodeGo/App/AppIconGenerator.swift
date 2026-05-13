import AppKit
import SwiftUI

/// Renders a "CG" monogram app icon programmatically.
/// Called once at launch to set NSApp.applicationIconImage.
enum AppIconGenerator {
    static func setAppIcon() {
        let size = CGSize(width: 1024, height: 1024)
        let icon = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // Background gradient: dark blue → purple
            let colors = [
                CGColor(srgbRed: 0.2, green: 0.35, blue: 0.7, alpha: 1),
                CGColor(srgbRed: 0.45, green: 0.25, blue: 0.65, alpha: 1),
            ]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: rect.width, y: rect.height), options: [])

            // Rounded rect clipping for smooth edges
            let path = CGPath(roundedRect: rect, cornerWidth: 180, cornerHeight: 180, transform: nil)
            ctx.addPath(path)
            ctx.clip()

            // White rounded pill background for the CG text
            let pillRect = CGRect(x: rect.midX - 160, y: rect.midY - 120, width: 320, height: 240)
            let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 60, cornerHeight: 60, transform: nil)
            ctx.addPath(pillPath)
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
            ctx.fillPath()

            // Draw "CG" text
            let text = "CG" as NSString
            let font = NSFont.systemFont(ofSize: 180, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(srgbRed: 0.2, green: 0.35, blue: 0.7, alpha: 1),
            ]
            let textSize = text.size(withAttributes: attrs)
            let textRect = CGRect(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2 - 4,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attrs)

            return true
        }
        icon.isTemplate = false
        NSApp.applicationIconImage = icon
    }

    /// Returns a small NSImage suitable for the menu bar icon (~18×18).
    static func menuBarIcon() -> NSImage {
        let size = CGSize(width: 20, height: 20)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // Circle background
            ctx.setFillColor(CGColor(srgbRed: 0.25, green: 0.25, blue: 0.25, alpha: 1))
            ctx.fillEllipse(in: rect.insetBy(dx: 1, dy: 1))

            // "CG" text in white
            let text = "CG" as NSString
            let font = NSFont.systemFont(ofSize: 11, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
            let textSize = text.size(withAttributes: attrs)
            let textRect = CGRect(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2 - 1,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attrs)
            return true
        }
        img.isTemplate = true
        return img
    }
}
