import CoreImage
import PhotosUI
import SwiftUI
import VisionKit

/// Reads one QR code: the camera when this iPhone supports live scanning, otherwise a photo or a
/// pasted code. The caller decides what the text means and whether to accept it.
struct QRScanSheet: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    var title: String
    var hint: String
    /// Returns nil to accept and close, or a message to show and keep scanning.
    var onCode: (String) async -> String?

    @State private var message: String?
    @State private var checking = false
    @State private var photo: PhotosPickerItem?
    @State private var pasted = ""
    @State private var cameraAvailable = DataScannerViewController.isSupported && DataScannerViewController.isAvailable

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(hint)
                        .font(look.type.callout)
                        .foregroundStyle(look.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if cameraAvailable {
                        LiveQRScanner { code in submit(code) }
                            .frame(height: 340)
                            .clipShape(RoundedRectangle(cornerRadius: look.shape.largeRadius))
                            .overlay(RoundedRectangle(cornerRadius: look.shape.largeRadius).strokeBorder(look.palette.rule, lineWidth: look.shape.borderWidth))
                            .accessibilityLabel("Camera viewfinder. Point it at the QR code.")
                    } else {
                        Label("The camera scanner isn’t available here. Choose a photo of the code, or paste it.", systemImage: "camera.metering.unknown")
                            .font(look.type.callout)
                            .foregroundStyle(look.palette.ink)
                            .lookPanel(padding: 14)
                    }
                    if checking {
                        HStack(spacing: 8) {
                            ProgressView().tint(look.palette.accent)
                            Text("Checking…").font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                        }
                    }
                    if let message {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(look.type.callout)
                            .foregroundStyle(look.palette.record)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Choose a photo of the code", systemImage: "photo")
                    }
                    .buttonStyle(.look(.secondary, fullWidth: true))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Or paste the code").font(look.type.headline).foregroundStyle(look.palette.ink)
                        TextField("Code", text: $pasted, axis: .vertical)
                            .lineLimit(1...4)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.callout, design: .monospaced))
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: look.shape.smallRadius).fill(look.palette.surfaceRaised))
                            .accessibilityIdentifier("qr.paste")
                        Button("Use this code") { submit(pasted) }
                            .buttonStyle(.look(.primary))
                            .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checking)
                            .accessibilityIdentifier("qr.use")
                    }
                }
                .padding(20)
            }
            .background { LookBackground() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    defer { photo = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self), let code = QRDecoder.decode(data) else {
                        message = "No QR code found in that photo."
                        return
                    }
                    submit(code)
                }
            }
        }
    }

    private func submit(_ raw: String) {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !checking else { return }
        checking = true
        message = nil
        Task {
            let result = await onCode(code)
            checking = false
            if let result { message = result } else { dismiss() }
        }
    }
}

enum QRDecoder {
    static func decode(_ imageData: Data) -> String? {
        guard let image = CIImage(data: imageData),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        else { return nil }
        return detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }

    /// A QR may carry a bare token or a link that ends in one (`sower://…/<token>`, `https://…/t/<token>`).
    static func token(from code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else { return trimmed }
        if let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "token" })?.value {
            return query
        }
        return url.lastPathComponent.isEmpty ? trimmed : url.lastPathComponent
    }
}

/// VisionKit's live scanner, reporting the first QR payload it recognizes.
private struct LiveQRScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        private var last: String?
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue, value != last {
                    last = value
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onCode(value)
                    return
                }
            }
        }
    }
}
