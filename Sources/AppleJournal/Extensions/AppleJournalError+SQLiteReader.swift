//
//  AppleJournalError+SQLiteReader.swift
//  AppleJournal
//
//  Created by David Sherlock on 2026.
//
//  The store is read through swift-sqlite-reader; its errors are reported
//  as this library's own, so callers and messages stay the same.
//

import Foundation
import SQLiteReader

extension AppleJournalError {

    /// This library's error for a reader's, opening the store at `url`.
    init(_ error: SQLiteReaderError, store url: URL) {
        switch error {
        case .notFound: self = .storeNotFound(url)
        case .permissionDenied: self = .permissionDenied(url)
        case .unreadable(_, let reason): self = .databaseError(reason)
        }
    }
}
