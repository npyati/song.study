import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

/// The same tokens as the web app: flat surfaces, hairlines, one orange.
enum T {
    static let ground   = Color.dynamic(0xF7F6F3, 0x0B0B0A)
    static let surface  = Color.dynamic(0xFFFFFF, 0x121211)
    static let surface2 = Color.dynamic(0xF4F2EE, 0x171715)
    static let line     = Color.dynamic(0xE5E2DB, 0x242421)
    static let line2    = Color.dynamic(0xD3CFC6, 0x34332E)
    static let ink      = Color.dynamic(0x121211, 0xF2F0EA)
    static let ink2     = Color.dynamic(0x6B6760, 0x8E8A81)
    static let ink3     = Color.dynamic(0xA09B93, 0x5E5A53)
    static let accent   = Color.dynamic(0xFF4A00, 0xFF5C1A)
    static let blue     = Color.dynamic(0x2F5CFF, 0x6486FF)

    static let passHex: [UInt32] = [0xFF4A00, 0xFF7A1A, 0xFF9E22, 0xFFC02E, 0xCBC733,
                                    0x84C33E, 0x27C08A, 0x2AA6C0, 0x3A6BFF, 0x7A4DFF]
    static func pass(_ p: Int) -> Color { Color(hex: passHex[((p - 1) % 10 + 10) % 10]) }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Lowercase mono micro-label.
struct Lbl: View {
    let text: String
    var color: Color = T.ink3
    init(_ text: String, color: Color = T.ink3) { self.text = text; self.color = color }
    var body: some View {
        Text(text.lowercased()).font(T.mono(9.5)).tracking(0.5).foregroundStyle(color)
    }
}

/// Flat hairline key. `on` fills it.
struct Key: ButtonStyle {
    var on = false
    var fill: Color = T.ink
    var square: CGFloat? = nil
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(T.mono(11))
            .foregroundStyle(on ? (fill == T.ink ? T.surface : .white) : T.ink2)
            .padding(.horizontal, square == nil ? 10 : 0)
            .frame(width: square, height: square ?? 30)
            .frame(minHeight: 30)
            .background(on ? fill : Color.clear)
            .overlay(Rectangle().stroke(on ? fill : T.line2, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}
