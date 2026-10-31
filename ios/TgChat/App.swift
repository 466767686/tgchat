import SwiftUI

@main
struct TgChatApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.scenePhase) private var scenePhase

    private var effectiveScheme: ColorScheme {
        switch app.themeMode {
        case .system: return systemScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        Group {
            if app.disguiseEnabled && app.locked {
                CalculatorView()
            } else if app.booting {
                SplashView()
            } else if app.isLoggedIn {
                ChatsView()
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(app.themeMode == .system ? nil : effectiveScheme)
        .overlay(alignment: .bottom) {
            if let toast = app.toast {
                ToastView(text: toast)
                    .transition(.opacity)
                    .task(id: toast) {
                        try? await Task.sleep(nanoseconds: 2_600_000_000)
                        await MainActor.run { app.clearToast() }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.toast)
        .onChange(of: scenePhase) { phase in
            app.appActive = phase == .active
            if phase == .active {
                KeepAliveAudio.shared.stop()
                Task {
                    await app.loadChats(silent: true)
                    await app.refreshActiveChat()
                }
            } else if app.isLoggedIn {
                KeepAliveAudio.shared.start()
            }
            if phase == .background { app.lock() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tgOpenChat)) { notification in
            if let chatId = notification.object as? String {
                app.requestOpenChat(chatId)
            }
        }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#4AA3F0"), Color(hex: "#3390EC")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 62))
                    .foregroundColor(.white)
                Text("Telegram")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white.opacity(0.9))
                    .padding(.top, 14)
            }
        }
    }
}
