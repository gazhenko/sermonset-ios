import CoreImage.CIFilterBuiltins
import SwiftUI

/// A QR code drawn on this iPhone. Nothing is sent anywhere to make it.
struct QRCodeImage: View {
    @Environment(\.look) private var look
    var text: String
    var label: String

    var body: some View {
        Group {
            if let image = Self.render(text) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode").resizable().scaledToFit().foregroundStyle(look.palette.inkTertiary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: look.shape.smallRadius).fill(Color.white))
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isImage)
    }

    static func render(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
