import SwiftUI

@main
struct KeePassIOSApp: App {
    @State private var model = AppModel()
    @State private var diagnostics = DiagnosticsRecorder()
    @Environment(\.scenePhase) private var scenePhase
    @State private var backgroundedAt: Date?

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(model)
                .environment(diagnostics)
                .onAppear { QuickCreateCenter.shared.attach(model) }
                .task { await model.load() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundedAt = Date()
                if model.settings.autoLockSeconds == 0 {
                    model.lockAll()
                }
            case .active:
                if let backgroundedAt,
                    Date().timeIntervalSince(backgroundedAt) >= TimeInterval(model.settings.autoLockSeconds)
                {
                    model.lockAll()
                }
                backgroundedAt = nil
            default:
                break
            }
        }
    }
}
