//
//  JournalStore.swift
//  AppleJournal
//
//  Created by David Sherlock on 2026.
//
//  Apple Journal's entries, read from its store — not by driving the app.
//  The store is a Core Data SQLite file in the `group.com.apple.moments`
//  container ("Moments" was Journal's working name), opened read-only
//  through swift-sqlite-reader. It is
//  not encrypted on the Mac (end-to-end encryption is iCloud's), but it sits
//  in a protected container: the app running this needs Full Disk Access.
//  Titles and words are RTF (swift-rich-text); a journal's name lives in a sync
//  record (CRDTStrings); attachments are files under `Attachments/`.
//

import Foundation
import RichText
import SQLiteReader

/// Apple Journal's journals and entries, read-only.
///
/// ```swift
/// let store = try JournalStore()
/// for entry in try store.entries() { print(entry.date, entry.title) }
/// print(try store.entry(id: 1).markdown)
/// ```
public final class JournalStore {

    /// Where Journal keeps its store.
    public static var defaultLocation: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.moments/Library/moments.sqlite")
    }

    private let store: SQLiteReader
    private let attachmentsFolder: URL

    /// Opens the store, read-only.
    ///
    /// - Parameter url: The store; the live one by default.
    /// - Throws: ``AppleJournalError/storeNotFound(_:)``, ``AppleJournalError/permissionDenied(_:)``
    ///   or ``AppleJournalError/databaseError(_:)``.
    public init(url: URL = JournalStore.defaultLocation) throws {
        do { store = try SQLiteReader(path: url, opening: .readOnly) } catch { throw AppleJournalError(error, store: url) }
        attachmentsFolder = url.deletingLastPathComponent().appendingPathComponent("Attachments")
        // A protected container lets the file stat and refuses the read: try one.
        guard !fetch("SELECT count(*) FROM ZJOURNALENTRYMO;").isEmpty else { throw AppleJournalError.permissionDenied(url) }
    }

    // MARK: - Journals

    /// Every journal, the built-in one first.
    public func journals() -> [Journal] {
        let counts = Dictionary(fetch("""
            SELECT j.Z_6JOURNALS, count(*) FROM Z_5JOURNALS j JOIN ZJOURNALENTRYMO e ON e.Z_PK = j.Z_5ENTRIES
            WHERE COALESCE(e.ZRECENTLYDELETED, 0) = 0 AND COALESCE(e.ZISFULLYREMOVED, 0) = 0 GROUP BY j.Z_6JOURNALS;
            """).compactMap { row in row[0].int.map { ($0, row[1].int ?? 0) } }, uniquingKeysWith: +)
        return fetch("""
            SELECT Z_PK, ZSORTCATEGORY, ZSORTORDER, ZMERGEABLEATTRIBUTES FROM ZJOURNALMO
            WHERE COALESCE(ZUSERDELETED, 0) = 0 ORDER BY ZSORTCATEGORY, ZSORTORDER, Z_PK;
            """).compactMap { row -> Journal? in
            guard let id = row[0].int else { return nil }
            let values = row[3].data.map(CRDTStrings.values) ?? [:]
            let builtIn = values["title"] == nil && (row[1].int ?? 0) < 0
            return Journal(id: id, name: values["title"] ?? (builtIn ? "Journal" : "Untitled journal"), color: values["color"],
                           icon: values["icon"], isBuiltIn: builtIn, entryCount: counts[id] ?? 0)
        }
    }

    // MARK: - Entries

    /// Entries, newest first.
    ///
    /// - Parameters:
    ///   - journal: Only this journal's, by ``Journal/id``.
    ///   - includeDeleted: Include Recently Deleted.
    public func entries(journal: Int? = nil, includeDeleted: Bool = false) -> [JournalEntry] {
        var clauses = ["COALESCE(e.ZISFULLYREMOVED, 0) = 0"]
        if !includeDeleted { clauses.append("COALESCE(e.ZRECENTLYDELETED, 0) = 0") }
        if let journal { clauses.append("e.Z_PK IN (SELECT Z_5ENTRIES FROM Z_5JOURNALS WHERE Z_6JOURNALS = \(journal))") }
        return rows(where: clauses.joined(separator: " AND "))
    }

    /// One entry, deleted or not.
    public func entry(id: Int) throws -> JournalEntry {
        guard let entry = rows(where: "e.Z_PK = \(id) AND COALESCE(e.ZISFULLYREMOVED, 0) = 0").first else {
            throw AppleJournalError.entryNotFound(id)
        }
        return entry
    }

    /// Entries whose title, words or attachments' places and transcripts
    /// hold `text`, ignoring case and accents; newest first.
    public func search(_ text: String, includeDeleted: Bool = false) -> [JournalEntry] {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return entries(includeDeleted: includeDeleted).filter { entry in
            ([entry.title, entry.text] + entry.attachments.flatMap { $0.places + [$0.transcript ?? ""] }).contains {
                $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    // MARK: - Reading rows

    private func rows(where clause: String) -> [JournalEntry] {
        let links = fetch("SELECT Z_5ENTRIES, Z_6JOURNALS FROM Z_5JOURNALS;")
        var journals: [Int: [Int]] = [:]
        for link in links {
            if let entry = link[0].int, let journal = link[1].int { journals[entry, default: []].append(journal) }
        }
        let attachments = attachmentsByEntry()
        return fetch("""
            SELECT e.Z_PK, e.ZID, e.ZTITLE, e.ZTEXT, e.ZENTRYDATE, e.ZCREATEDDATE, e.ZUPDATEDDATE, e.ZISDRAFT, e.ZFLAGGED,
                   e.ZRECENTLYDELETED FROM ZJOURNALENTRYMO e WHERE \(clause)
            ORDER BY COALESCE(e.ZENTRYDATE, e.ZCREATEDDATE) DESC, e.Z_PK DESC;
            """).compactMap { row -> JournalEntry? in
            guard let id = row[0].int else { return nil }
            let created = Self.date(row[5])
            return JournalEntry(id: id, uuid: row[1].uuid ?? "", title: RichText.plain(row[2].data),
                                text: RichText.plain(row[3].data), markdown: RichText.markdown(row[3].data),
                                date: Self.date(row[4]) ?? created ?? .distantPast, created: created,
                                updated: Self.date(row[6]), isDraft: row[7].bool ?? false,
                                isBookmarked: row[8].bool ?? false, isRecentlyDeleted: row[9].bool ?? false,
                                journals: (journals[id] ?? []).sorted(), attachments: attachments[id] ?? [])
        }
    }

    /// Every entry's attachments, streak markers left out (Journal's own
    /// bookkeeping, not something added).
    private func attachmentsByEntry() -> [Int: [JournalAttachment]] {
        let files = Dictionary(fetch("SELECT ZASSET, ZFILEPATH FROM ZJOURNALENTRYASSETFILEATTACHMENTMO ORDER BY ZINDEX;")
            .compactMap { row -> (Int, String)? in
                guard let asset = row[0].int, let path = row[1].string else { return nil }
                return (asset, path)
            }, uniquingKeysWith: { first, _ in first })
        var found: [Int: [JournalAttachment]] = [:]
        for row in fetch("""
            SELECT Z_PK, ZENTRY, ZID, ZASSETTYPE, ZSOURCE, ZCREATEDDATE, ZASSETMETADATA FROM ZJOURNALENTRYASSETMO
            WHERE ZENTRY IS NOT NULL AND COALESCE(ZISFULLYREMOVED, 0) = 0 AND COALESCE(ZISHIDDEN, 0) = 0
              AND COALESCE(ZASSETTYPE, '') != 'streakEvent' ORDER BY Z_PK;
            """) {
            guard let pk = row[0].int, let entry = row[1].int else { continue }
            let metadata = AttachmentDetails.object(row[6].data)
            let file = files[pk].map { attachmentsFolder.appendingPathComponent($0) }
                .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            found[entry, default: []].append(JournalAttachment(
                id: row[2].uuid ?? String(pk), kind: row[3].string ?? "unknown", source: row[4].string,
                added: Self.date(row[5]), file: file, places: AttachmentDetails.places(metadata),
                transcript: AttachmentDetails.transcript(metadata) ?? AttachmentDetails.handwriting(metadata),
                drawing: AttachmentDetails.drawing(metadata)))
        }
        return found
    }

    /// Every row `sql` returns; none when it cannot run — the queries here are fixed text.
    private func fetch(_ sql: String) -> [SQLiteRow] {
        (try? store.rows(sql)) ?? []
    }

    /// A Core Data date column: seconds since 2001, any value (Journal's own rule,
    /// not `appleDate`, which reads 0 as "never").
    private static func date(_ value: SQLiteValue) -> Date? {
        value.double.map(Date.init(timeIntervalSinceReferenceDate:))
    }
}
