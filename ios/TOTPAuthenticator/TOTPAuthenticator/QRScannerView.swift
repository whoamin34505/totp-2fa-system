import SwiftUI
import VisionKit
import Vision

struct QRScannerView: UIViewControllerRepresentable {
    var isActive: Bool
    var onCodeScanned: (String) -> Void
    
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .fast,
            recognizesMultipleItems: true,
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

        if coordinator.isActive != isActive {
            coordinator.isActive = isActive
            if isActive {
                coordinator.hasScanned = false
            }
        }

        if isActive && !coordinator.hasScanned && !uiViewController.isScanning {
            do {
                try uiViewController.startScanning()
            } catch {
                print("Не удалось запустить сканер: \(error)")
            }
        } else if !isActive && uiViewController.isScanning {
            uiViewController.stopScanning()
        }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }
    
    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCodeScanned: (String) -> Void
        var isActive = false
        var hasScanned = false
        
        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }
        
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            process(addedItems, scanner: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            process(updatedItems, scanner: dataScanner)
        }

        private func process(_ items: [RecognizedItem], scanner: DataScannerViewController) {
            guard isActive, !hasScanned else { return }

            for item in items {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue,
                      OTPAuthParser().parse(payload) != nil else {
                    continue
                }

                hasScanned = true
                scanner.stopScanning()
                onCodeScanned(payload)
                return
            }
        }
    }
}
