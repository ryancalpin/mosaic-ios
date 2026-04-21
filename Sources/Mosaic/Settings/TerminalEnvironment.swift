// Sources/Mosaic/Settings/TerminalEnvironment.swift
import SwiftUI

// MARK: - TerminalFontSize

private struct TerminalFontSizeKey: EnvironmentKey {
    static let defaultValue: Double = 13.0
}

// MARK: - OutputDensity

private struct OutputDensityKey: EnvironmentKey {
    static let defaultValue: OutputDensity = .standard
}

// MARK: - ShowNativeRenderers

private struct ShowNativeRenderersKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

// MARK: - ShowTimestamps

private struct ShowTimestampsKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

// MARK: - EnvironmentValues extensions

extension EnvironmentValues {
    var terminalFontSize: Double {
        get { self[TerminalFontSizeKey.self] }
        set { self[TerminalFontSizeKey.self] = newValue }
    }
    var outputDensity: OutputDensity {
        get { self[OutputDensityKey.self] }
        set { self[OutputDensityKey.self] = newValue }
    }
    var showNativeRenderers: Bool {
        get { self[ShowNativeRenderersKey.self] }
        set { self[ShowNativeRenderersKey.self] = newValue }
    }
    var showTimestamps: Bool {
        get { self[ShowTimestampsKey.self] }
        set { self[ShowTimestampsKey.self] = newValue }
    }
}
