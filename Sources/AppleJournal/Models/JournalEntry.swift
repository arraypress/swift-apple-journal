//
//  JournalEntry.swift
//  AppleJournal
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One entry: its title and words, when it is for, and what was added to it.
public struct JournalEntry: Sendable, Codable, Equatable {
    /// Its row in the store.
    public let id: Int
    /// Its identifier, the name of its attachments' folder.
    public let uuid: String
    /// Its title, as plain text; empty when it has none.
    public let title: String
    /// Its words, as plain text.
    public let text: String
    /// Its words as Markdown: bold, italic, strikethrough and lists kept.
    public let markdown: String
    /// The day it is for — which the writer can set — or when it was made.
    public let date: Date
    /// When it was made.
    public let created: Date?
    /// When it was last changed.
    public let updated: Date?
    /// Whether it is still a draft.
    public let isDraft: Bool
    /// Whether it is bookmarked.
    public let isBookmarked: Bool
    /// Whether it is in Recently Deleted.
    public let isRecentlyDeleted: Bool
    /// The journals it is in, by ``Journal/id``.
    public let journals: [Int]
    /// What was added to it, in its order.
    public let attachments: [JournalAttachment]

    /// An entry.
    public init(id: Int, uuid: String, title: String, text: String, markdown: String, date: Date, created: Date?,
                updated: Date?, isDraft: Bool, isBookmarked: Bool, isRecentlyDeleted: Bool, journals: [Int],
                attachments: [JournalAttachment]) {
        self.id = id
        self.uuid = uuid
        self.title = title
        self.text = text
        self.markdown = markdown
        self.date = date
        self.created = created
        self.updated = updated
        self.isDraft = isDraft
        self.isBookmarked = isBookmarked
        self.isRecentlyDeleted = isRecentlyDeleted
        self.journals = journals
        self.attachments = attachments
    }
}
