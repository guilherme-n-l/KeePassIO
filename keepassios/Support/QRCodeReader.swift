import SwiftUI
import UIKit
import Vision
import VisionKit

/// Reads QR codes: live from the camera, or from an image such as a
/// screenshot of a site's two-factor setup page.
enum QRCodeReader {
    /// Whether this device can scan with the camera (and the user hasn't
    /// denied camera access).
    static var canScanWithCamera: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    /// The text of every QR code found in the image.
    @concurrent
    nonisolated static func payloads(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }
}

/// The camera, looking for a QR code; calls `onFound` with the first one.
struct QRCodeScannerView: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFound: onFound)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onFound: (String) -> Void
        private var didFind = false

        init(onFound: @escaping (String) -> Void) {
            self.onFound = onFound
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !didFind else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    didFind = true
                    onFound(payload)
                    return
                }
            }
        }
    }
}
