// Sources/Mosaic/UI/Settings/SettingsSheet.swift
import SwiftUI

@MainActor
struct SettingsSheet: View {
    @Environment(\.dismiss)      private var dismiss
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var s = settings
        NavigationStack {
            Form {
                // MARK: Appearance
                Section("Appearance") {
                    Picker("Theme", selection: $s.theme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: Terminal
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Font Size")
                            Spacer()
                            Text("\(Int(s.terminalFontSize)) pt")
                                .font(.custom("JetBrains Mono", size: 12))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $s.terminalFontSize, in: 9...20, step: 1)
                            .tint(.mosaicAccent)

                        // Live preview
                        Text("$ ls -la ~/projects")
                            .font(.custom("JetBrains Mono", size: s.terminalFontSize))
                            .foregroundColor(.mosaicTextPri)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.mosaicBg)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.vertical, 4)

                    Picker("Output Density", selection: $s.outputDensity) {
                        ForEach(OutputDensity.allCases, id: \.self) { d in
                            Text(d.label).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Terminal")
                }

                // MARK: Display
                Section("Display") {
                    Toggle("Native Renderers", isOn: $s.showNativeRenderers)
                    Toggle("Show Timestamps", isOn: $s.showTimestamps)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.custom("JetBrains Mono", size: 12).weight(.bold))
                        .foregroundColor(.mosaicAccent)
                }
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
    }
}
