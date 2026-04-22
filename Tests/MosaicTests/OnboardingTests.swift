// Tests/MosaicTests/OnboardingTests.swift
import Foundation
import Testing
@testable import Mosaic

@Suite("Onboarding")
@MainActor
struct OnboardingTests {

    @Test func defaultOnboardingNotCompleted() {
        // Reset to known state
        UserDefaults.standard.removeObject(forKey: "mosaic.hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "mosaic.hasSeenFirstNativeRender")
        let settings = AppSettings()
        #expect(!settings.hasCompletedOnboarding)
        #expect(!settings.hasSeenFirstNativeRender)
    }

    @Test func onboardingFlagPersists() {
        let settings = AppSettings()
        settings.hasCompletedOnboarding = true
        #expect(UserDefaults.standard.bool(forKey: "mosaic.hasCompletedOnboarding"))
        // cleanup
        UserDefaults.standard.removeObject(forKey: "mosaic.hasCompletedOnboarding")
    }

    @Test func firstNativeRenderFlagPersists() {
        let settings = AppSettings()
        settings.hasSeenFirstNativeRender = true
        #expect(UserDefaults.standard.bool(forKey: "mosaic.hasSeenFirstNativeRender"))
        // cleanup
        UserDefaults.standard.removeObject(forKey: "mosaic.hasSeenFirstNativeRender")
    }
}
