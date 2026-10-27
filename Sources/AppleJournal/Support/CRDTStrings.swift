//
//  CRDTStrings.swift
//  AppleJournal
//
//  Created by David Sherlock on 2026.
//
//  A journal's name, colour and icon live in a sync record: `crdt`, a
//  32-bit version, then a protobuf whose last part is a table of strings —
//  each value followed by its key (`Garden notes`, `title`, `Mint`,
//  `color`…). Read structurally: the table is the run of length-prefixed
//  field-2 strings that ends exactly at the record's end, every one of them
//  printable text; a value is taken only when the string after it is a key
//  this knows. Pure.
//

import Foundation

enum CRDTStrings {

    /// The keys a journal's record holds.
    static let keys: Set<String> = ["title", "color", "icon"]

    /// The record's string table, or nil when it is not one.
    static func table(_ data: Data) -> [String]? {
        let bytes = [UInt8](data)
        guard bytes.count > 8, Array(bytes.prefix(4)) == Array("crdt".utf8) else { return nil }
        for start in 8..<bytes.count where bytes[start] == 0x12 {
            if let strings = run(bytes, from: start) { return strings }
        }
        return nil
    }

    /// The strings when `bytes` from `start` to the end is nothing but
    /// field-2 strings of printable text; nil otherwise.
    static func run(_ bytes: [UInt8], from start: Int) -> [String]? {
        var index = start
        var strings: [String] = []
        while index < bytes.count {
            guard bytes[index] == 0x12, let (length, next) = varint(bytes, at: index + 1),
                  length > 0, next + length <= bytes.count,
                  let text = String(bytes: bytes[next..<(next + length)], encoding: .utf8),
                  text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
            strings.append(text)
            index = next + length
        }
        return strings
    }

    /// A protobuf varint at `index`: its value and the index after it.
    static func varint(_ bytes: [UInt8], at index: Int) -> (Int, Int)? {
        var value = 0, shift = 0, at = index
        while at < bytes.count, shift < 35 {
            let byte = bytes[at]
            value |= Int(byte & 0x7F) << shift
            at += 1
            if byte & 0x80 == 0 { return (value, at) }
            shift += 7
        }
        return nil
    }

    /// The values by key: each string followed by a known key.
    static func values(_ data: Data) -> [String: String] {
        guard let strings = table(data) else { return [:] }
        var found: [String: String] = [:]
        for (value, key) in zip(strings, strings.dropFirst()) where keys.contains(key) && !keys.contains(value) {
            found[key] = found[key] ?? value
        }
        return found
    }
}
