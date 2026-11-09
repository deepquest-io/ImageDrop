// ImageDrop by deepquest | https://deepquest.code511.com/blog
import Foundation
import ImageIO

enum OutputFormat: String, CaseIterable, Identifiable {
    case webp, jpeg, png, heic, avif, tiff, gif, bmp, jpeg2000

    var id: String { rawValue }

    var label: String {
        switch self {
        case .webp: return "WebP"
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .avif: return "AVIF"
        case .tiff: return "TIFF"
        case .gif: return "GIF"
        case .bmp: return "BMP"
        case .jpeg2000: return "JPEG 2000"
        }
    }

    var fileExtension: String {
        switch self {
        case .webp: return "webp"
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .avif: return "avif"
        case .tiff: return "tiff"
        case .gif: return "gif"
        case .bmp: return "bmp"
        case .jpeg2000: return "jp2"
        }
    }

    /// Uniform Type Identifier used by ImageIO.
    var typeIdentifier: String {
        switch self {
        case .webp: return "org.webmproject.webp"
        case .jpeg: return "public.jpeg"
        case .png: return "public.png"
        case .heic: return "public.heic"
        case .avif: return "public.avif"
        case .tiff: return "public.tiff"
        case .gif: return "com.compuserve.gif"
        case .bmp: return "com.microsoft.bmp"
        case .jpeg2000: return "public.jpeg-2000"
        }
    }

    var usesQuality: Bool {
        switch self {
        case .webp, .jpeg, .heic, .avif, .jpeg2000: return true
        default: return false
        }
    }

    var supportsAlpha: Bool {
        switch self {
        case .jpeg, .bmp: return false
        default: return true
        }
    }

    /// WebP is always available (bundled libwebp); everything else depends on what
    /// this Mac's ImageIO can write (e.g. AVIF only on newer macOS versions).
    static let available: [OutputFormat] = {
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        return allCases.filter { $0 == .webp || writable.contains($0.typeIdentifier) }
    }()
}

enum WebPMode: String, CaseIterable, Identifiable {
    case smart, lossy, lossless

    var id: String { rawValue }

    var label: String {
        switch self {
        case .smart: return "Smart"
        case .lossy: return "Lossy"
        case .lossless: return "Lossless"
        }
    }

    var help: String {
        switch self {
        case .smart:
            return "Lossy for photos. For PNG/GIF/screenshots it also tries lossless and keeps it if it's about the same size — sharper text and edges."
        case .lossy:
            return "Always lossy (smallest files). Uses the slowest, best-compressing settings plus sharp colour conversion."
        case .lossless:
            return "Pixel-perfect output. Best for graphics, logos and screenshots; large for photos."
        }
    }
}

struct ConversionSettings {
    var format: OutputFormat
    var quality: Double        // 1–100
    var webpMode: WebPMode
    var maxDimension: Int      // 0 = keep original size
    var keepMetadata: Bool
}
