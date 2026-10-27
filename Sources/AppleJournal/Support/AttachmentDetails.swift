//
//  AttachmentDetails.swift
//  AppleJournal
//
//  Created by David Sherlock on 2026.
//
//  What an attachment's metadata says that a person would want: the places
//  on a map, what was said in a recording, the words recognised in a
//  sketch and the sketch itself. The metadata is JSON after a one-byte
//  version (MEASURED: 0x01 on every kind); that byte is skipped. Pure.
//

import Foundation

enum AttachmentDetails {

    /// The place names on a map attachment, in order, each once.
    static func places(_ metadata: [String: Any]) -> [String] {
        let visits = (metadata["visitsData"] as? [[String: Any]]) ?? []
        var seen: Set<String> = []
        return visits.compactMap { $0["placeName"] as? String }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// A recording's transcript: its segments' text, joined.
    static func transcript(_ metadata: [String: Any]) -> String? {
        let segments = (metadata["transcriptSegments"] as? [Any]) ?? []
        let words = segments.compactMap { segment -> String? in
            (segment as? String) ?? ((segment as? [String: Any])?["text"] as? String) ?? ((segment as? [String: Any])?["string"] as? String)
        }
        let joined = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    /// The JSON object in metadata bytes — after the version byte, or
    /// anything else before the first `{` — or empty.
    static func object(_ data: Data?) -> [String: Any] {
        guard let data, let start = data.firstIndex(of: UInt8(ascii: "{")) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data[start...]) as? [String: Any]) ?? [:]
    }

    /// The words Journal recognised in a sketch's handwriting, on one line.
    static func handwriting(_ metadata: [String: Any]) -> String? {
        let text = (metadata["indexableContent"] as? String)?.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        return text?.isEmpty == false ? text : nil
    }

    /// A sketch's PencilKit drawing, decoded from its base64.
    static func drawing(_ metadata: [String: Any]) -> Data? {
        (metadata["drawingData"] as? String).flatMap { Data(base64Encoded: $0) }
    }
}
