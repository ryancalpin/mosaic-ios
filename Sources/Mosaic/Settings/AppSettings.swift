// Sources/Mosaic/Settings/AppSettings.swift
import SwiftUI

// MARK: - Enums

enum AppTheme: String, CaseIterable {
    case dark, light, system

    var colorScheme: ColorScheme? {
        switch self {
        case .dark:   return .dark
        case .light:  return .light
        case .system: return nil
        }
    }

    var label: String { rawValue.capitalized }
}

enum OutputDensity: String, CaseIterable {
    case compact, standard, spacious

    var verticalPadding: CGFloat {
        switch self {
        case .compact:  return 6
        case .standard: return 10
        case .spacious: return 16
        }
    }

    var label: String { rawValue.capitalized }
}

// MARK: - AppSettings

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "mosaic.theme") }
    }
    var terminalFontSize: Double {
        didSet { UserDefaults.standard.set(terminalFontSize, forKey: "mosaic.fontSize") }
    }
    var outputDensity: OutputDensity {
        didSet { UserDefaults.standard.set(outputDensity.rawValue, forKey: "mosaic.density") }
    }
    var showNativeRenderers: Bool {
        didSet { UserDefaults.standard.set(showNativeRenderers, forKey: "mosaic.nativeRenderers") }
    }
    var showTimestamps: Bool {
        didSet { UserDefaults.standard.set(showTimestamps, forKey: "mosaic.timestamps") }
    }
    var claudeApiKey: String {
        didSet { UserDefaults.standard.set(claudeApiKey, forKey: "mosaic.claudeApiKey") }
    }
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "mosaic.hasCompletedOnboarding") }
    }
    var hasSeenFirstNativeRender: Bool {
        didSet { UserDefaults.standard.set(hasSeenFirstNativeRender, forKey: "mosaic.hasSeenFirstNativeRender") }
    }

    init() {
        let ud = UserDefaults.standard
        theme            = AppTheme(rawValue: ud.string(forKey: "mosaic.theme") ?? "") ?? .dark
        let size         = ud.double(forKey: "mosaic.fontSize")
        terminalFontSize = size > 0 ? size : 13.0
        outputDensity    = OutputDensity(rawValue: ud.string(forKey: "mosaic.density") ?? "") ?? .standard
        showNativeRenderers = ud.object(forKey: "mosaic.nativeRenderers") as? Bool ?? true
        showTimestamps   = ud.object(forKey: "mosaic.timestamps") as? Bool ?? false
        claudeApiKey     = ud.string(forKey: "mosaic.claudeApiKey") ?? ""
        hasCompletedOnboarding  = ud.bool(forKey: "mosaic.hasCompletedOnboarding")
        hasSeenFirstNativeRender = ud.bool(forKey: "mosaic.hasSeenFirstNativeRender")
    }
}
