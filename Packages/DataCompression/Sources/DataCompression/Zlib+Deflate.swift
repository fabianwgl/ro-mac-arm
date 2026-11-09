//
//  Zlib+Deflate.swift
//  DataCompression
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import CZlib

extension Zlib {
    /// Compresses bytes into a zlib stream (RFC 1950), the format `inflate` reads.
    ///
    /// Returns `nil` only when zlib runs out of memory: the output buffer is sized with `compressBound`.
    public static func deflate(_ bytes: [UInt8]) -> [UInt8]? {
        var length = compressBound(uLong(bytes.count))
        var output = [UInt8](repeating: 0, count: Int(length))

        guard compress2(&output, &length, bytes, uLong(bytes.count), Z_DEFAULT_COMPRESSION) == Z_OK else {
            return nil
        }

        output.removeLast(output.count - Int(length))
        return output
    }
}
