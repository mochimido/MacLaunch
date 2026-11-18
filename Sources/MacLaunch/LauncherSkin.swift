import AppKit

/// The same part boundaries as CLaunch's skin.xml; drawing is native and uses original assets.
struct LauncherSkin {
    let name: LauncherSkinName
    var isDark: Bool { name == .solidDark }
    var frame: NSColor { color(light: 0xE7E9EC, dark: 0x25272C, glass: 0xB6CBE8) }
    var background: NSColor { color(light: 0xF4F4F4, dark: 0x303238, glass: 0xDCE8F6) }
    var ink: NSColor { color(light: 0x1A1A1A, dark: 0xECEEF2, glass: 0x294E79) }
    var muted: NSColor { color(light: 0x72767D, dark: 0xA3A8B1, glass: 0x5C7899) }
    var border: NSColor { color(light: 0xC4C8CE, dark: 0x16181C, glass: 0x8AA7CE) }
    var button: NSColor { color(light: 0xFAFAFA, dark: 0x36383E, glass: 0xC2D6F2) }
    var hover: NSColor { color(light: 0xE2E5E9, dark: 0x4B4E57, glass: 0xDDEBFC) }
    var pressed: NSColor { color(light: 0xD7E7F6, dark: 0x365779, glass: 0x9FBBE2) }
    var accent: NSColor { color(light: 0x3476BA, dark: 0x83B7EB, glass: 0x3B6FA9) }
    var radius: CGFloat { name == .glass ? 5 : 3 }

    private func color(light: UInt32, dark: UInt32, glass: UInt32) -> NSColor {
        NSColor(hex: name == .solidDark ? dark : name == .glass ? glass : light)
    }

    func drawButton(in rect: NSRect, hovered: Bool, down: Bool, selected: Bool, empty: Bool) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        let fill = down ? pressed : hovered || selected ? hover : button
        if name == .glass && !empty {
            NSGradient(starting: fill.blended(withFraction: 0.28, of: .white)!, ending: fill)?.draw(in: path, angle: 90)
        } else {
            (empty && !hovered && !selected ? background : fill).setFill()
            path.fill()
        }
        (selected ? accent : border.withAlphaComponent(empty && !hovered ? 0.35 : 0.65)).setStroke()
        path.lineWidth = selected ? 1.4 : 0.7
        path.stroke()
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(calibratedRed: CGFloat((hex >> 16) & 255) / 255,
                  green: CGFloat((hex >> 8) & 255) / 255,
                  blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

struct LauncherLayout {
    let preferences: Preferences
    let searching: Bool
    var columns: Int { preferences.columns }
    var cellWidth: CGFloat { 58 }
    var cellHeight: CGFloat { preferences.showLabels ? 58 : 44 }
    let pitch: CGFloat = 4
    let captionHeight: CGFloat = 28
    let tabHeight: CGFloat = 30
    var searchHeight: CGFloat { searching ? 32 : 0 }
    var gridWidth: CGFloat { CGFloat(columns) * (cellWidth + pitch) - pitch }
    var gridHeight: CGFloat { CGFloat(preferences.visibleRows) * (cellHeight + pitch) - pitch }
    var width: CGFloat { gridWidth + 22 }
    var height: CGFloat { captionHeight + tabHeight + searchHeight + gridHeight + 38 }
    var gridY: CGFloat { captionHeight + searchHeight + (preferences.tabPosition == .top ? tabHeight : 0) + 6 }
    var tabY: CGFloat { preferences.tabPosition == .top ? captionHeight + searchHeight : gridY + gridHeight + 6 }
    var gridFrame: NSRect { NSRect(x: 11, y: gridY, width: gridWidth, height: gridHeight) }
    var footerFrame: NSRect { NSRect(x: 11, y: height - 23, width: gridWidth, height: 17) }
    func frame(for slot: Int) -> NSRect {
        NSRect(x: CGFloat(slot % columns) * (cellWidth + pitch), y: CGFloat(slot / columns) * (cellHeight + pitch), width: cellWidth, height: cellHeight)
    }
}
