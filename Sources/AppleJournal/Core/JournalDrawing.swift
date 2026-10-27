//
//  JournalDrawing.swift
//  AppleJournal
//
//  Created by David Sherlock on 2026.
//
//  A sketch, drawn. Journal keeps a sketch inside the attachment's metadata
//  as PaperKit markup (`%PPK…` — MEASURED: PencilKit refuses it as
//  malformed), with no image file. PaperKit draws it into a context that
//  counts from the top left; the page is a whole canvas (768 × 1500 points
//  on the test sketch) with the strokes in one corner, so the picture is
//  cropped to its ink (InkBounds) and laid on white so dark ink shows.
//

import AppKit
import Foundation
import PaperKit

/// Drawing Journal's sketches.
@available(macOS 26.0, *)
public enum JournalDrawing {

    /// A PNG of a sketch cropped to its ink, or nil when the data is not a
    /// sketch or holds no ink.
    ///
    /// - Parameters:
    ///   - data: The sketch's data (``JournalAttachment/drawing``).
    ///   - scale: Pixels per point.
    public static func png(_ data: Data, scale: CGFloat = 2) async -> Data? {
        guard let markup = try? PaperMarkup(dataRepresentation: data), markup.bounds.width > 0, markup.bounds.height > 0 else {
            return nil
        }
        let frame = markup.bounds
        let width = Int(frame.width * scale), height = Int(frame.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // PaperKit draws from the top left; a bitmap counts from the bottom.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -frame.minX, y: -frame.minY)
        await markup.draw(in: context, frame: frame)
        guard let image = context.makeImage(), let pixels = context.data else { return nil }
        let bytes = UnsafeBufferPointer(start: pixels.assumingMemoryBound(to: UInt8.self), count: width * height * 4)
        guard let ink = InkBounds.rect(bytes, width: width, height: height, margin: Int(16 * scale)),
              let cropped = image.cropping(to: ink) else { return nil }
        return NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])
    }
}
