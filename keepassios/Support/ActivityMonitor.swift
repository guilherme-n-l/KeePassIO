import SwiftUI
import UIKit

/// Remembers when the user last touched the app, for the idle auto-lock.
///
/// A gesture recognizer on the window sees every touch without taking
/// part in gesture handling, so it can't interfere with any control.
@MainActor
final class ActivityMonitor {
    private(set) var lastActivity = Date()

    func recordActivity() {
        lastActivity = Date()
    }

    /// Attaches the recognizer to the window of the view it's placed in.
    struct Installer: UIViewRepresentable {
        let monitor: ActivityMonitor

        func makeUIView(context: Context) -> InstallerView {
            InstallerView(monitor: monitor)
        }

        func updateUIView(_ uiView: InstallerView, context: Context) {}
    }

    final class InstallerView: UIView {
        private let monitor: ActivityMonitor
        private var recognizer: TouchRecorder?

        init(monitor: ActivityMonitor) {
            self.monitor = monitor
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, recognizer == nil else { return }
            let recognizer = TouchRecorder(monitor: monitor)
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
        }
    }

    /// Records each touch, then fails so other gestures proceed normally.
    final class TouchRecorder: UIGestureRecognizer {
        private let monitor: ActivityMonitor

        init(monitor: ActivityMonitor) {
            self.monitor = monitor
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            monitor.recordActivity()
            state = .failed
        }
    }
}

/// Applies the accent color to UIKit's tint as well, which menu pickers,
/// alerts and other UIKit-drawn controls use instead of SwiftUI's `.tint`.
struct WindowTint: UIViewRepresentable {
    let color: Color

    func makeUIView(context: Context) -> TintView {
        TintView()
    }

    func updateUIView(_ uiView: TintView, context: Context) {
        uiView.tint = UIColor(color)
    }

    final class TintView: UIView {
        var tint: UIColor? {
            didSet { apply() }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        /// Sets the tint on the window and on every presented screen: a
        /// sheet's root view keeps the tint it was presented with, so an
        /// open sheet (Settings, where the color is picked) would otherwise
        /// show its menu pickers in the previous color.
        private func apply() {
            guard let window else { return }
            window.tintColor = tint
            var controller = window.rootViewController?.presentedViewController
            while let current = controller {
                current.view.tintColor = tint
                controller = current.presentedViewController
            }
        }
    }
}
