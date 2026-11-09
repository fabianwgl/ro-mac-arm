//
//  GuildEmblemCodec.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import CoreGraphics
import DataCompression
import Foundation
import RagnarokCore

/// Reads and writes guild emblems the way rAthena stores them: a zlib compressed BMP of 24 by 24 pixels, magenta
/// (`FF00FF`) for transparent pixels.
///
/// rAthena keeps whatever the master's client uploaded and sends it back unchanged in `ZC_GUILD_EMBLEM_IMG`. Clients
/// since 2019 upload a GIF instead, so the decoder also takes a plain GIF or BMP.
enum GuildEmblemCodec {
    static let side = 24

    // MARK: - Decode

    /// The emblem as an image with the magenta pixels transparent, `nil` when the data is not a readable image.
    static func decode(_ bytes: [UInt8]) -> CGImage? {
        guard let image = CGImageCreateWithData(Data(imageBytes(from: bytes))) else {
            return nil
        }

        return image.removingMagentaPixels() ?? image
    }

    /// Inflates the data when it is a zlib stream and returns it untouched otherwise.
    static func imageBytes(from bytes: [UInt8]) -> [UInt8] {
        guard !isImage(bytes), let inflated = try? Zlib.inflate(bytes, capacity: 2048).data else {
            return bytes
        }

        return inflated
    }

    private static func isImage(_ bytes: [UInt8]) -> Bool {
        let bmp: [UInt8] = [0x42, 0x4d]
        let gif: [UInt8] = [0x47, 0x49, 0x46, 0x38]
        return bytes.starts(with: bmp) || bytes.starts(with: gif)
    }

    // MARK: - Encode

    /// The upload data for `CZ_REGISTER_GUILD_EMBLEM_IMG`: the image scaled to 24 by 24, transparent pixels turned
    /// magenta, written as a 24-bit BMP and compressed into a zlib stream.
    static func encode(_ image: CGImage) -> [UInt8]? {
        guard let bmp = bmp(from: image) else {
            return nil
        }

        return Zlib.deflate(bmp)
    }

    /// A bottom-up 24-bit BMP. A row is 72 bytes, so it needs no padding, and the file is 1782 bytes.
    ///
    /// A pixel that is less than half opaque becomes magenta. The others are written fully opaque, so the soft edge
    /// of a scaled image does not turn pink.
    static func bmp(from image: CGImage) -> [UInt8]? {
        let side = Self.side
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: side * bytesPerRow)

        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }

            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else {
            return nil
        }

        let headerSize = 54
        let pixelBytes = side * side * 3
        var data: [UInt8] = []
        data.reserveCapacity(headerSize + pixelBytes)

        func append16(_ value: Int) {
            data += [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)]
        }

        func append32(_ value: Int) {
            data += (0..<4).map { UInt8((value >> (8 * $0)) & 0xff) }
        }

        // BITMAPFILEHEADER
        data += [0x42, 0x4d]
        append32(headerSize + pixelBytes)
        append32(0)
        append32(headerSize)
        // BITMAPINFOHEADER
        append32(40)
        append32(side)
        append32(side)
        append16(1)
        append16(24)
        append32(0)
        append32(pixelBytes)
        append32(2835)
        append32(2835)
        append32(0)
        append32(0)

        for row in stride(from: side - 1, through: 0, by: -1) {
            for column in 0..<side {
                let offset = row * bytesPerRow + column * 4
                let alpha = Int(pixels[offset + 3])
                guard alpha >= 128 else {
                    data += [0xff, 0x00, 0xff]
                    continue
                }

                // The context holds premultiplied color.
                let color = (0..<3).map { UInt8(min(Int(pixels[offset + $0]) * 255 / alpha, 255)) }
                data += [color[2], color[1], color[0]]
            }
        }

        return data
    }
}
