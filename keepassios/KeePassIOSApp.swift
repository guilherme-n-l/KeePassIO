import KPAppState
import SwiftUI

@main
struct KeePassIOSApp: App {
    @State private var model = AppModel()
    @State private var diagnostics = DiagnosticsRecorder()
    @State private var activity = ActivityMonitor()
    @State private var autoFill = AutoFillSetup()
    @Environment(\.scenePhase) private var scenePhase
    @State private var backgroundedAt: Date?

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(model)
                .environment(diagnostics)
                .environment(autoFill)
                .background(ActivityMonitor.Installer(monitor: activity))
                .overlay {
                    // Hides the contents from the app switcher snapshot and
                    // from anyone glancing at Control Center, as the database
                    // may be locking underneath.
                    if scenePhase != .active {
                        PrivacyCover()
                    }
                }
                .onAppear { QuickCreateCenter.shared.attach(model) }
                .task { await model.load() }
                .task { await autoFill.refresh() }
                .task { await lockWhenIdle() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .inactive:
                // Notification Center, Control Center, the app switcher and
                // system prompts (Face ID included) only make the app
                // inactive. It's still on screen, so nothing locks; the
                // cover hides its contents meanwhile.
                break
            case .background:
                // The app has left the screen (home, another app, screen
                // lock). "Immediately" locks now; the timed settings count
                // from here.
                if backgroundedAt == nil {
                    backgroundedAt = Date()
                }
                if model.settings.autoLockSeconds == 0 {
                    model.lockAll()
                }
            case .active:
                let timeout = model.settings.autoLockSeconds
                if timeout > 0, let backgroundedAt, Date().timeIntervalSince(backgroundedAt) >= TimeInterval(timeout) {
                    model.lockAll()
                }
                backgroundedAt = nil
                activity.recordActivity()
                // The user may have just turned AutoFill on in Settings.
                Task { await autoFill.refresh() }
            @unknown default:
                break
            }
        }
    }

    /// Locks open databases once the user hasn't touched the app for the
    /// auto-lock time, even with the app on screen.
    private func lockWhenIdle() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            let timeout = model.settings.autoLockSeconds
            guard timeout > 0, model.hasUnlockedDatabase else { continue }
            if Date().timeIntervalSince(activity.lastActivity) >= TimeInterval(timeout) {
                model.lockAll()
            }
        }
    }
}

/// Shown over the app whenever it isn't the active app.
private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
