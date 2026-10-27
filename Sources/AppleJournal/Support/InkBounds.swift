//
//  InkBounds.swift
//  AppleJournal
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

/// Where the ink is on a white page. Pure.
enum InkBounds {

    /// The smallest rectangle (rows from the top) holding every pixel that
    /// is not white, grown by `margin` and kept on the page; nil when the
    /// page is blank. `bytes` is RGBA, row after row, from the top.
    static func rect(_ bytes: UnsafeBufferPointer<UInt8>, width: Int, height: Int, margin: Int, threshold: UInt8 = 245) -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width {
                let i = row + x * 4
                if bytes[i] < threshold || bytes[i + 1] < threshold || bytes[i + 2] < threshold {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        let left = max(0, minX - margin), top = max(0, minY - margin)
        let right = min(width, maxX + 1 + margin), bottom = min(height, maxY + 1 + margin)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
