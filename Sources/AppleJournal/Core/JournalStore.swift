//
//  JournalStore.swift
//  AppleJournal
//
//  Created by David Sherlock on 2026.
//
//  Apple Journal's entries, read from its store — not by driving the app.
//  The store is a Core Data SQLite file in the `group.com.apple.moments`
//  container ("Moments" was Journal's working name), opened read-only. It is
//  not encrypted on the Mac (end-to-end encryption is iCloud's), but it sits
//  in a protected container: the app running this needs Full Disk Access.
//  Titles and words are RTF (RichText); a journal's name lives in a sync
//  record (CRDTStrings); attachments are files under `Attachments/`.
//

import Foundation
import SQLite3

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

    private let handle: OpaquePointer
    private let attachmentsFolder: URL

    /// Opens the store, read-only.
    ///
    /// - Parameter url: The store; the live one by default.
    /// - Throws: ``AppleJournalError/storeNotFound(_:)``, ``AppleJournalError/permissionDenied(_:)``
    ///   or ``AppleJournalError/databaseError(_:)``.
    public init(url: URL = JournalStore.defaultLocation) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw AppleJournalError.storeNotFound(url) }
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw AppleJournalError.permissionDenied(url) }
        var opened: OpaquePointer?
        guard sqlite3_open_v2("file:\(url.path)?mode=ro", &opened, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open"
            sqlite3_close(opened)
            throw message.lowercased().contains("authoriz") || message.lowercased().contains("permission")
                ? AppleJournalError.permissionDenied(url) : AppleJournalError.databaseError(message)
        }
        handle = opened
        attachmentsFolder = url.deletingLastPathComponent().appendingPathComponent("Attachments")
        // A protected container lets the file stat and refuses the read: try one.
        guard !SQLiteRows.rows(handle, "SELECT count(*) FROM ZJOURNALENTRYMO;").isEmpty else {
            sqlite3_close(handle)
            throw AppleJournalError.permissionDenied(url)
        }
    }

    deinit { sqlite3_close(handle) }

    // MARK: - Journals

    /// Every journal, the built-in one first.
    public func journals() -> [Journal] {
        let counts = Dictionary(SQLiteRows.rows(handle, """
            SELECT j.Z_6JOURNALS, count(*) FROM Z_5JOURNALS j JOIN ZJOURNALENTRYMO e ON e.Z_PK = j.Z_5ENTRIES
            WHERE COALESCE(e.ZRECENTLYDELETED, 0) = 0 AND COALESCE(e.ZISFULLYREMOVED, 0) = 0 GROUP BY j.Z_6JOURNALS;
            """).compactMap { row in (row[0] as? Int64).map { (Int($0), Int(row[1] as? Int64 ?? 0)) } }, uniquingKeysWith: +)
        return SQLiteRows.rows(handle, """
            SELECT Z_PK, ZSORTCATEGORY, ZSORTORDER, ZMERGEABLEATTRIBUTES FROM ZJOURNALMO
            WHERE COALESCE(ZUSERDELETED, 0) = 0 ORDER BY ZSORTCATEGORY, ZSORTORDER, Z_PK;
            """).compactMap { row -> Journal? in
            guard let id = row[0] as? Int64 else { return nil }
            let values = (row[3] as? Data).map(CRDTStrings.values) ?? [:]
            let builtIn = values["title"] == nil && (row[1] as? Int64 ?? 0) < 0
            return Journal(id: Int(id), name: values["title"] ?? (builtIn ? "Journal" : "Untitled journal"), color: values["color"],
                           icon: values["icon"], isBuiltIn: builtIn, entryCount: counts[Int(id)] ?? 0)
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
        let links = SQLiteRows.rows(handle, "SELECT Z_5ENTRIES, Z_6JOURNALS FROM Z_5JOURNALS;")
        var journals: [Int: [Int]] = [:]
        for link in links {
            if let entry = link[0] as? Int64, let journal = link[1] as? Int64 { journals[Int(entry), default: []].append(Int(journal)) }
        }
        let attachments = attachmentsByEntry()
        return SQLiteRows.rows(handle, """
            SELECT e.Z_PK, e.ZID, e.ZTITLE, e.ZTEXT, e.ZENTRYDATE, e.ZCREATEDDATE, e.ZUPDATEDDATE, e.ZISDRAFT, e.ZFLAGGED,
                   e.ZRECENTLYDELETED FROM ZJOURNALENTRYMO e WHERE \(clause)
            ORDER BY COALESCE(e.ZENTRYDATE, e.ZCREATEDDATE) DESC, e.Z_PK DESC;
            """).compactMap { row -> JournalEntry? in
            guard let id = (row[0] as? Int64).map(Int.init) else { return nil }
            let created = SQLiteRows.date(row[5])
            return JournalEntry(id: id, uuid: SQLiteRows.uuid(row[1]) ?? "", title: RichText.plain(row[2] as? Data),
                                text: RichText.plain(row[3] as? Data), markdown: RichText.markdown(row[3] as? Data),
                                date: SQLiteRows.date(row[4]) ?? created ?? .distantPast, created: created,
                                updated: SQLiteRows.date(row[6]), isDraft: (row[7] as? Int64 ?? 0) != 0,
                                isBookmarked: (row[8] as? Int64 ?? 0) != 0, isRecentlyDeleted: (row[9] as? Int64 ?? 0) != 0,
                                journals: (journals[id] ?? []).sorted(), attachments: attachments[id] ?? [])
        }
    }

    /// Every entry's attachments, streak markers left out (Journal's own
    /// bookkeeping, not something added).
    private func attachmentsByEntry() -> [Int: [JournalAttachment]] {
        let files = Dictionary(SQLiteRows.rows(handle, "SELECT ZASSET, ZFILEPATH FROM ZJOURNALENTRYASSETFILEATTACHMENTMO ORDER BY ZINDEX;")
            .compactMap { row -> (Int, String)? in
                guard let asset = row[0] as? Int64, let path = row[1] as? String else { return nil }
                return (Int(asset), path)
            }, uniquingKeysWith: { first, _ in first })
        var found: [Int: [JournalAttachment]] = [:]
        for row in SQLiteRows.rows(handle, """
            SELECT Z_PK, ZENTRY, ZID, ZASSETTYPE, ZSOURCE, ZCREATEDDATE, ZASSETMETADATA FROM ZJOURNALENTRYASSETMO
            WHERE ZENTRY IS NOT NULL AND COALESCE(ZISFULLYREMOVED, 0) = 0 AND COALESCE(ZISHIDDEN, 0) = 0
              AND COALESCE(ZASSETTYPE, '') != 'streakEvent' ORDER BY Z_PK;
            """) {
            guard let pk = row[0] as? Int64, let entry = row[1] as? Int64 else { continue }
            let metadata = AttachmentDetails.object(row[6] as? Data)
            let file = files[Int(pk)].map { attachmentsFolder.appendingPathComponent($0) }
                .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            found[Int(entry), default: []].append(JournalAttachment(
                id: SQLiteRows.uuid(row[2]) ?? String(pk), kind: row[3] as? String ?? "unknown", source: row[4] as? String,
                added: SQLiteRows.date(row[5]), file: file, places: AttachmentDetails.places(metadata),
                transcript: AttachmentDetails.transcript(metadata) ?? AttachmentDetails.handwriting(metadata),
                drawing: AttachmentDetails.drawing(metadata)))
        }
        return found
    }
}
