// Sources/Mosaic/Extensions/Color+Mosaic.swift
import SwiftUI

// Returns a Color that automatically switches between dark and light hex values
// based on the effective color scheme (driven by .preferredColorScheme at the root).
private func adaptive(dark: String, light: String) -> Color {
    Color(UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
    })
}

extension Color {
    // Backgrounds
    static let mosaicBg       = adaptive(dark: "#09090B", light: "#F7F7FA")
    static let mosaicSurface1 = adaptive(dark: "#111115", light: "#EDEDF2")
    static let mosaicSurface2 = adaptive(dark: "#17171C", light: "#E4E4EB")
    static let mosaicBorder   = adaptive(dark: "#1E1E26", light: "#CECEDA")

    // Accent / protocol colors — unchanged across themes
    static let mosaicAccent   = Color(hex: "#00D4AA")
    static let mosaicBlue     = Color(hex: "#4A9EFF")
    static let mosaicPurple   = Color(hex: "#A78BFA")

    // Text
    static let mosaicTextPri  = adaptive(dark: "#D8E4F0", light: "#1A1E2E")
    static let mosaicTextSec  = adaptive(dark: "#3A4A58", light: "#607084")
    static let mosaicTextMut  = adaptive(dark: "#1E2830", light: "#C0CAD4")

    // Semantic
    static let mosaicGreen    = Color(hex: "#3DFF8F")
    static let mosaicYellow   = Color(hex: "#FFD060")
    static let mosaicRed      = Color(hex: "#FF4D6A")
    static let mosaicWarn     = Color(hex: "#FFB020")
}
