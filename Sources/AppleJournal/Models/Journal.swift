//
//  Journal.swift
//  AppleJournal
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One journal in the Journal app — the built-in one, or one made in it.
public struct Journal: Sendable, Codable, Equatable {
    /// Its row in the store: what entries refer to it by.
    public let id: Int
    /// Its name; the built-in journal, which stores none, is "Journal".
    public let name: String
    /// The colour chosen for it (`Mint`…), when one was.
    public let color: String?
    /// The SF Symbol chosen for it (`leaf.fill`…), when one was.
    public let icon: String?
    /// Whether it is the journal the app starts with.
    public let isBuiltIn: Bool
    /// How many entries are in it (recently deleted ones not counted).
    public let entryCount: Int

    /// A journal.
    public init(id: Int, name: String, color: String?, icon: String?, isBuiltIn: Bool, entryCount: Int) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.isBuiltIn = isBuiltIn
        self.entryCount = entryCount
    }
}
