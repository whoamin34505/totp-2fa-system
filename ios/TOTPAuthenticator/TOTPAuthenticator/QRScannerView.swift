import SwiftUI
import VisionKit
import Vision

struct QRScannerView: UIViewControllerRepresentable {
    var isActive: Bool
    var onCodeScanned: (String) -> Bool
    var onScannerUnavailable: () -> Void
    
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .fast,
            recognizesMultipleItems: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.onCodeScanned = onCodeScanned
        coordinator.onScannerUnavailable = onScannerUnavailable

        if coordinator.isActive != isActive {
            coordinator.isActive = isActive
            if isActive {
                coordinator.didFinishScanning = false
            }
        }

        if isActive && !coordinator.didFinishScanning && !uiViewController.isScanning {
            do {
                try uiViewController.startScanning()
            } catch {
                coordinator.scannerBecameUnavailable()
            }
        } else if !isActive && uiViewController.isScanning {
            uiViewController.stopScanning()
        }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        coordinator.isActive = false
        uiViewController.stopScanning()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned, onScannerUnavailable: onScannerUnavailable)
    }
    
    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCodeScanned: (String) -> Bool
        var onScannerUnavailable: () -> Void
        var isActive = false
        var didFinishScanning = false
        private var rejectedPayload: String?
        
        init(onCodeScanned: @escaping (String) -> Bool, onScannerUnavailable: @escaping () -> Void) {
            self.onCodeScanned = onCodeScanned
            self.onScannerUnavailable = onScannerUnavailable
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            scannerBecameUnavailable()
        }

        func scannerBecameUnavailable() {
            guard isActive, !didFinishScanning else { return }
            didFinishScanning = true
            Task { @MainActor in
                guard isActive else { return }
                onScannerUnavailable()
            }
        }
        
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            process(addedItems, scanner: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            process(updatedItems, scanner: dataScanner)
        }

        private func process(_ items: [RecognizedItem], scanner: DataScannerViewController) {
            guard isActive, !didFinishScanning else { return }

            for item in items {
                guard case .barcode(let barcode) = item else { continue }
                let payload = barcode.payloadStringValue ?? ""
                guard payload != rejectedPayload else { continue }

                didFinishScanning = true
                scanner.stopScanning()
                rejectedPayload = onCodeScanned(payload) ? nil : payload
                return
            }
        }
    }
}
