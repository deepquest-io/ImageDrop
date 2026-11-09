// ImageDrop by deepquest | https://deepquest.code511.com/blog
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

struct ConversionResult {
    let output: URL
    let bytes: Int64
    let width: Int
    let height: Int
    let thumbnail: CGImage?
    let note: String?
}

enum ConversionError: LocalizedError {
    case unreadable
    case decodeFailed
    case encodeFailed(String)
    case tooLarge(Int, Int)

    var errorDescription: String? {
        switch self {
        case .unreadable: return "Not an image macOS can read"
        case .decodeFailed: return "Couldn't decode the image"
        case .encodeFailed(let why): return "Encoding failed: \(why)"
        case .tooLarge(let w, let h):
            return "\(w)×\(h) exceeds WebP's 16383 px limit — pick a smaller Max size"
        }
    }
}

enum Converter {

    static func convert(source: URL, to output: URL, settings: ConversionSettings) throws -> ConversionResult {
        guard let src = CGImageSourceCreateWithURL(source as CFURL,
                                                   [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(src) > 0 else {
            throw ConversionError.unreadable
        }

        let props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]) ?? [:]
        let image = try decode(src, props: props, maxDimension: settings.maxDimension)

        let sourceType = (CGImageSourceGetType(src) as String?).flatMap { UTType($0) }

        let data: Data
        var note: String? = nil

        switch settings.format {
        case .webp:
            let result = try WebPEncoder.encode(image,
                                                quality: Float(settings.quality),
                                                mode: settings.webpMode,
                                                sourceType: sourceType)
            data = result.data
            note = result.lossless ? "lossless" : "lossy"
        default:
            data = try encodeWithImageIO(image, format: settings.format, settings: settings, sourceProps: props)
        }

        try data.write(to: output, options: .withoutOverwriting)

        return ConversionResult(output: output,
                                bytes: Int64(data.count),
                                width: image.width,
                                height: image.height,
                                thumbnail: makeThumbnail(image, maxSide: 96),
                                note: note)
    }

    // MARK: - Decoding

    /// Decodes the first frame, applies EXIF orientation and optional downscaling.
    private static func decode(_ src: CGImageSource, props: [CFString: Any], maxDimension: Int) throws -> CGImage {
        let width = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let fullMax = max(width, height)

        var target = fullMax
        if maxDimension > 0, fullMax > maxDimension { target = maxDimension }

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // honour EXIF orientation
            kCGImageSourceShouldCacheImmediately: true
        ]
        if target > 0 { options[kCGImageSourceThumbnailMaxPixelSize] = target }

        if let img = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) {
            return img
        }
        if let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            return img
        }
        throw ConversionError.decodeFailed
    }

    // MARK: - ImageIO encoding (JPEG, PNG, HEIC, AVIF, TIFF, GIF, BMP, JPEG 2000)

    private static func encodeWithImageIO(_ input: CGImage,
                                          format: OutputFormat,
                                          settings: ConversionSettings,
                                          sourceProps: [CFString: Any]) throws -> Data {
        var image = input
        if !format.supportsAlpha && image.hasAlphaChannel {
            image = flattenOnWhite(image)
        }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData,
                                                          format.typeIdentifier as CFString, 1, nil) else {
            throw ConversionError.encodeFailed("\(format.label) isn't supported on this Mac")
        }

        var props: [CFString: Any] = [:]

        if settings.keepMetadata {
            if var exif = sourceProps[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
                exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
                props[kCGImagePropertyExifDictionary] = exif
            }
            for key in [kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
                if let value = sourceProps[key] { props[key] = value }
            }
            if var tiff = sourceProps[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                props[kCGImagePropertyTIFFDictionary] = tiff
            }
        }

        // Pixels are already rotated upright during decode.
        props[kCGImagePropertyOrientation] = 1

        if format.usesQuality {
            props[kCGImageDestinationLossyCompressionQuality] = max(0.01, min(1.0, settings.quality / 100.0))
        }
        if format == .tiff {
            var tiff = (props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]
            tiff[kCGImagePropertyTIFFCompression] = 5   // LZW
            props[kCGImagePropertyTIFFDictionary] = tiff
        }

        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ConversionError.encodeFailed("ImageIO couldn't write \(format.label)")
        }
        return out as Data
    }

    // MARK: - Helpers

    private static func flattenOnWhite(_ image: CGImage) -> CGImage {
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let preferred = (image.colorSpace?.model == .rgb) ? image.colorSpace! : srgb

        func context(_ space: CGColorSpace) -> CGContext? {
            CGContext(data: nil, width: image.width, height: image.height,
                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        }
        guard let ctx = context(preferred) ?? context(srgb) else { return image }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: rect)
        return ctx.makeImage() ?? image
    }

    private static func makeThumbnail(_ image: CGImage, maxSide: Int) -> CGImage? {
        let scale = min(1.0, Double(maxSide) / Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width) * scale))
        let h = max(1, Int(Double(image.height) * scale))
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}

extension CGImage {
    var hasAlphaChannel: Bool {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }
}
