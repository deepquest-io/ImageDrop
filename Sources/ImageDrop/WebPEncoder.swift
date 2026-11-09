// ImageDrop by deepquest | https://deepquest.code511.com/blog
import Foundation
import CoreGraphics
import Accelerate
import UniformTypeIdentifiers
import libwebp

/// WebP encoding through libwebp, tuned for "small file, high quality":
///  • method 6 (slowest / best compression search)
///  • sharp RGB→YUV conversion (keeps colour edges and fine detail crisp)
///  • photo preset for camera sources (better noise/texture handling)
///  • Smart mode: graphics also get a lossless attempt, kept if it's about the same size
enum WebPEncoder {

    struct Output {
        let data: Data
        let lossless: Bool
    }

    static func encode(_ image: CGImage, quality: Float, mode: WebPMode, sourceType: UTType?) throws -> Output {
        guard image.width <= Int(WEBP_MAX_DIMENSION), image.height <= Int(WEBP_MAX_DIMENSION) else {
            throw ConversionError.tooLarge(image.width, image.height)
        }

        let pixels = try RGBABuffer(image)
        let isPhotoSource = sourceType.map { t in
            t.conforms(to: .jpeg) || t.conforms(to: .heic) || t.conforms(to: .heif) || t.conforms(to: .rawImage)
        } ?? false
        let isGraphicSource = sourceType.map { t in
            t.conforms(to: .png) || t.conforms(to: .gif) || t.conforms(to: .bmp) ||
            t.conforms(to: .tiff) || t.conforms(to: .ico)
        } ?? false
        let preset = isPhotoSource ? WEBP_PRESET_PHOTO : WEBP_PRESET_DEFAULT

        switch mode {
        case .lossy:
            return Output(data: try run(pixels, lossless: false, quality: quality, preset: preset), lossless: false)

        case .lossless:
            return Output(data: try run(pixels, lossless: true, quality: quality, preset: preset), lossless: true)

        case .smart:
            let lossy = try run(pixels, lossless: false, quality: quality, preset: preset)
            // Lossless is expensive on huge images and pointless for camera photos.
            guard isGraphicSource, pixels.width * pixels.height <= 12_000_000 else {
                return Output(data: lossy, lossless: false)
            }
            if let lossless = try? run(pixels, lossless: true, quality: quality, preset: preset),
               Double(lossless.count) <= Double(lossy.count) * 1.15 {
                return Output(data: lossless, lossless: true)
            }
            return Output(data: lossy, lossless: false)
        }
    }

    private static func run(_ buffer: RGBABuffer, lossless: Bool, quality: Float, preset: WebPPreset) throws -> Data {
        var config = WebPConfig()
        guard WebPConfigPreset(&config, preset, quality) != 0 else {
            throw ConversionError.encodeFailed("libwebp version mismatch")
        }

        if lossless {
            // Level 6 = libwebp's default lossless effort (method 4, quality 75).
            guard WebPConfigLosslessPreset(&config, 6) != 0 else {
                throw ConversionError.encodeFailed("invalid lossless preset")
            }
            config.exact = 0               // allow RGB under fully-transparent pixels to be simplified
        } else {
            config.method = 6              // best compression
            config.use_sharp_yuv = 1       // sharper chroma, fewer colour-bleed artefacts
            config.alpha_quality = 90
            config.alpha_filtering = 2       // best alpha prediction
        }
        config.thread_level = 1

        guard WebPValidateConfig(&config) != 0 else {
            throw ConversionError.encodeFailed("invalid WebP configuration")
        }

        var picture = WebPPicture()
        guard WebPPictureInit(&picture) != 0 else {
            throw ConversionError.encodeFailed("libwebp version mismatch")
        }
        // Keep ARGB so the encoder performs the (sharp) YUV conversion itself.
        picture.use_argb = 1
        picture.width = Int32(buffer.width)
        picture.height = Int32(buffer.height)

        let imported = buffer.hasAlpha
            ? WebPPictureImportRGBA(&picture, buffer.pixels, Int32(buffer.stride))
            : WebPPictureImportRGBX(&picture, buffer.pixels, Int32(buffer.stride))
        guard imported != 0 else {
            WebPPictureFree(&picture)
            throw ConversionError.encodeFailed("out of memory")
        }

        let writer = UnsafeMutablePointer<WebPMemoryWriter>.allocate(capacity: 1)
        WebPMemoryWriterInit(writer)
        defer {
            WebPMemoryWriterClear(writer)
            writer.deallocate()
            WebPPictureFree(&picture)
        }

        picture.writer = WebPMemoryWrite
        picture.custom_ptr = UnsafeMutableRawPointer(writer)

        guard WebPEncode(&config, &picture) != 0 else {
            throw ConversionError.encodeFailed("libwebp error \(picture.error_code.rawValue)")
        }
        guard let mem = writer.pointee.mem, writer.pointee.size > 0 else {
            throw ConversionError.encodeFailed("empty output")
        }
        return Data(bytes: mem, count: writer.pointee.size)
    }
}

/// 8-bit sRGB, non-premultiplied RGBA pixels — the layout libwebp expects.
final class RGBABuffer {
    let width: Int
    let height: Int
    let stride: Int
    let pixels: UnsafeMutablePointer<UInt8>
    let hasAlpha: Bool

    init(_ image: CGImage) throws {
        let w = image.width
        let h = image.height
        let rowBytes = w * 4
        let count = rowBytes * h

        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        buf.initialize(repeating: 0, count: count)

        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: rowBytes,
                                  space: srgb,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                            | CGBitmapInfo.byteOrder32Big.rawValue) else {
            buf.deallocate()
            throw ConversionError.encodeFailed("couldn't allocate pixel buffer")
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Only treat the image as transparent if some pixel actually is.
        var alpha = false
        if image.hasAlphaChannel {
            var i = 3
            while i < count {
                if buf[i] != 255 { alpha = true; break }
                i += 4
            }
        }
        if alpha {
            var src = vImage_Buffer(data: UnsafeMutableRawPointer(buf),
                                    height: vImagePixelCount(h),
                                    width: vImagePixelCount(w),
                                    rowBytes: rowBytes)
            var dst = src
            _ = vImageUnpremultiplyData_RGBA8888(&src, &dst, vImage_Flags(kvImageNoFlags))
        }

        width = w
        height = h
        stride = rowBytes
        pixels = buf
        hasAlpha = alpha
    }

    deinit { pixels.deallocate() }
}
