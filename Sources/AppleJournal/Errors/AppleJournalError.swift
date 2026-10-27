//
//  AppleJournalError.swift
//  AppleJournal
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Why Journal's store could not be read.
public enum AppleJournalError: Error, Sendable, Equatable, LocalizedError {
    /// There is no store: Journal has never been opened on this Mac.
    case storeNotFound(URL)
    /// macOS refused it: the app running this needs Full Disk Access.
    case permissionDenied(URL)
    /// SQLite could not read it.
    case databaseError(String)
    /// No entry has that id.
    case entryNotFound(Int)

    /// A sentence for a person.
    public var errorDescription: String? {
        switch self {
        case .storeNotFound: return "no Journal store on this Mac — open the Journal app once"
        case .permissionDenied: return "macOS refused Journal's store — give the app running this Full Disk Access"
        case .databaseError(let message): return "Journal's store could not be read: \(message)"
        case .entryNotFound(let id): return "no Journal entry \(id)"
        }
    }
}
