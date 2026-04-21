// Sources/Mosaic/Extensions/Color+Hex.swift
import SwiftUI

extension Color {
    init(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        guard scanner.scanHexInt64(&rgb) else {
            self.init(red: 0.5, green: 0.5, blue: 0.5)
            return
        }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >>  8) & 0xFF) / 255.0
        let b = Double( rgb        & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

extension UIColor {
    convenience init(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        guard scanner.scanHexInt64(&rgb) else {
            self.init(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            return
        }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >>  8) & 0xFF) / 255.0
        let b = CGFloat( rgb        & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
