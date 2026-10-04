import KPObservability
import SwiftUI

/// Shows timing histograms recorded on this device and exports them as a
/// file for bug reports. Contains only operation names, counts and
/// durations, never database contents.
struct DiagnosticsView: View {
    @Environment(DiagnosticsRecorder.self) private var diagnostics

    var body: some View {
        List {
            Section {
                ForEach(diagnostics.histograms.keys.sorted { $0.displayName < $1.displayName }, id: \.self) { span in
                    if let histogram = diagnostics.histograms[span] {
                        LabeledContent(span.displayName) {
                            let median = Double(histogram.quantileUpperBound(0.5) ?? 0) / 1_000_000
                            Text(
                                "\(histogram.count)× · p50 < \(median, format: .number.precision(.fractionLength(1))) ms"
                            )
                        }
                    }
                }
            } footer: {
                Text(
                    "Timings of operations on this device. Nothing is uploaded; export the file to attach it to a bug report."
                )
            }
            if let file = diagnostics.exportFile() {
                ShareLink(item: file) {
                    Label("Export Diagnostics", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("Diagnostics")
        .onAppear { diagnostics.refresh() }
    }
}
