import Foundation
import KPObservability
import Observation
import UIKit

/// Installs the app's trace backends and exposes the on-device histograms.
@MainActor
@Observable
final class DiagnosticsRecorder {
    private let backend = HistogramBackend()
    private(set) var histograms: [SpanName: LatencyHistogram] = [:]

    init() {
        Trace.bootstrap(Trace.defaultBackends() + [backend])
    }

    func refresh() {
        histograms = backend.histograms
    }

    /// Writes the export to a temporary file for the share sheet.
    func exportFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KeePassIO-diagnostics.json")
        let os = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        guard let data = try? backend.exportJSON(appVersion: Bundle.main.appVersion, osVersion: os) else { return nil }
        try? data.write(to: url, options: .atomic)
        return url
    }
}
