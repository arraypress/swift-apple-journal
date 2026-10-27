//
//  SQLiteRows.swift
//  AppleJournal
//
//  Created by David Sherlock on 2026.
//

import Foundation
import SQLite3

/// Rows from a query, each column as Int64, Double, String or Data.
enum SQLiteRows {

    /// Every row `sql` returns, binding nothing — the queries here are fixed text.
    static func rows(_ handle: OpaquePointer, _ sql: String) -> [[Any?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var results: [[Any?]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [Any?] = []
            for column in 0..<sqlite3_column_count(statement) {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row.append(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: row.append(sqlite3_column_double(statement, column))
                case SQLITE_TEXT: row.append(String(cString: sqlite3_column_text(statement, column)))
                case SQLITE_BLOB:
                    let count = sqlite3_column_bytes(statement, column)
                    if let pointer = sqlite3_column_blob(statement, column), count > 0 {
                        row.append(Data(bytes: pointer, count: Int(count)))
                    } else { row.append(nil) }
                default: row.append(nil)
                }
            }
            results.append(row)
        }
        return results
    }

    /// A Core Data date column: seconds since 2001.
    static func date(_ value: Any?) -> Date? {
        (value as? Double).map(Date.init(timeIntervalSinceReferenceDate:))
            ?? (value as? Int64).map { Date(timeIntervalSinceReferenceDate: Double($0)) }
    }

    /// A 16-byte identifier column as a UUID string.
    static func uuid(_ value: Any?) -> String? {
        guard let data = value as? Data, data.count == 16 else { return nil }
        return data.withUnsafeBytes { NSUUID(uuidBytes: $0.bindMemory(to: UInt8.self).baseAddress!).uuidString }
    }
}
