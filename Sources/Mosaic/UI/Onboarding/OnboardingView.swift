// Sources/Mosaic/UI/Onboarding/OnboardingView.swift
import SwiftUI
import SwiftData

@MainActor
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @State private var page = 0
    @State private var connectionSaved = false

    var body: some View {
        TabView(selection: $page) {
            WelcomePage(onNext: { withAnimation { page = 1 } })
                .tag(0)

            ConnectPage(
                connectionSaved: $connectionSaved,
                onNext: { withAnimation { page = 2 } }
            )
            .tag(1)

            DonePage(onFinish: {
                settings.hasCompletedOnboarding = true
            })
            .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .background(Color.mosaicBg)
        .ignoresSafeArea()
    }
}

// MARK: - Welcome Page

private struct WelcomePage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Text("✦")
                    .font(.system(size: 56))
                    .foregroundColor(.mosaicAccent)

                Text("Mosaic")
                    .font(.largeTitle.bold())
                    .foregroundColor(.mosaicTextPri)

                Text("A native terminal runtime")
                    .font(.title3)
                    .foregroundColor(.mosaicTextSec)
            }

            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    icon: "terminal",
                    title: "Not a terminal emulator",
                    detail: "Commands run on your real server over SSH or Mosh. Mosaic intercepts the output and renders it natively."
                )
                FeatureRow(
                    icon: "rectangle.3.group",
                    title: "Native SwiftUI output",
                    detail: "docker ps, git status, ls — rendered as interactive cards, not walls of text."
                )
                FeatureRow(
                    icon: "eye",
                    title: "Always raw underneath",
                    detail: "Tap any native block to see the original output. Your data is never altered."
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            Button(action: onNext) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.mosaicAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.mosaicAccent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.mosaicTextPri)
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.mosaicTextSec)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Connect Page

private struct ConnectPage: View {
    @Binding var connectionSaved: Bool
    let onNext: () -> Void
    @State private var showForm = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Connect your first server")
                    .font(.title2.bold())
                    .foregroundColor(.mosaicTextPri)
                Text("SSH or Mosh — your server stays in control.")
                    .font(.subheadline)
                    .foregroundColor(.mosaicTextSec)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 60)
            .padding(.horizontal, 24)

            if showForm {
                // Inline connection form — no navigation needed
                ConnectionFormView(
                    connection: nil,
                    inlineMode: true,
                    onCancel: { showForm = false },
                    onSave: { _ in
                        connectionSaved = true
                        onNext()
                    }
                )
            } else {
                Spacer()
                VStack(spacing: 16) {
                    Button(action: { showForm = true }) {
                        Label("Add Server", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.mosaicAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 32)

                    Button(action: onNext) {
                        Text("Skip for now")
                            .font(.subheadline)
                            .foregroundColor(.mosaicTextSec)
                    }
                }
                .padding(.bottom, 48)
            }
        }
    }
}

// MARK: - Done Page

private struct DonePage: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.mosaicGreen)

                Text("You're ready")
                    .font(.largeTitle.bold())
                    .foregroundColor(.mosaicTextPri)

                Text("Run your first command.\nWatch it render natively.")
                    .font(.title3)
                    .foregroundColor(.mosaicTextSec)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button(action: onFinish) {
                Text("Open Mosaic")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.mosaicAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}
