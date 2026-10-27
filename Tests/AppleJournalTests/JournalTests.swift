//
//  JournalTests.swift
//  AppleJournal
//
//  Created by David Sherlock on 2026.
//
//  Journal's store with no Journal: a synthetic database with the real
//  tables and columns, entries written as RTF the way AppKit writes it, a
//  journal's sync record built like the real one byte for byte, metadata
//  with its version byte, and the pure readers on their own. Every name,
//  place and word here is invented.
//

import AppKit
import Foundation
import SQLite3
import XCTest
@testable import AppleJournal

final class JournalTests: XCTestCase {

    // MARK: - Pure readers

    /// A journal record as Journal writes one: `crdt`, version 7, binary, then the string table.
    static func record(_ strings: [String]) -> Data {
        var bytes = Array("crdt".utf8) + [7, 0, 0, 0] + [0x0A, 0x3B, 0x22, 0x39, 0x0A, 0x03, 0x01, 0x03, 0x12, 0x0A, 0x08, 0x01]
        for string in strings {
            let utf8 = Array(string.utf8)
            bytes += [0x12, UInt8(utf8.count)] + utf8
        }
        return Data(bytes)
    }

    func testAJournalsNameColourAndIconComeFromItsRecord() {
        let values = CRDTStrings.values(Self.record(["Garden notes", "title", "Mint", "color", "leaf.fill", "icon"]))
        XCTAssertEqual(values, ["title": "Garden notes", "color": "Mint", "icon": "leaf.fill"])
        XCTAssertEqual(CRDTStrings.values(Self.record(["title", "title"])), [:], "a key is never a value")
        XCTAssertEqual(CRDTStrings.values(Data("not a record".utf8)), [:])
        XCTAssertNil(CRDTStrings.table(Data("crdt".utf8)))
    }

    func testTheTableMustRunToTheEnd() {
        var bytes = [UInt8](Self.record(["Garden notes", "title"]))
        bytes.append(0x01)   // a stray byte after the table
        XCTAssertNil(CRDTStrings.table(Data(bytes)), "a table that does not end the record is not the table")
        let otherField = Self.record(["Garden notes", "title"]) + Data([0x1A, 3]) + Data("abc".utf8)
        XCTAssertNil(CRDTStrings.table(otherField), "only field-2 strings make the table")
    }

    func testMetadataSkipsItsVersionByte() {
        let map = Data([0x01]) + Data(#"{"visitsData":[{"placeName":"Harbour Café"},{"placeName":"Old Mill"},{"placeName":"Harbour Café"}]}"#.utf8)
        XCTAssertEqual(AttachmentDetails.places(AttachmentDetails.object(map)), ["Harbour Café", "Old Mill"], "each place once")
        let sketch = AttachmentDetails.object(Data([0x01]) + Data(#"{"indexableContent":"\n\nBuy\nseeds","drawingData":"JVBQSw=="}"#.utf8))
        XCTAssertEqual(AttachmentDetails.handwriting(sketch), "Buy seeds")
        XCTAssertEqual(AttachmentDetails.drawing(sketch), Data("%PPK".utf8))
        XCTAssertEqual(AttachmentDetails.transcript(["transcriptSegments": [["text": "hello"], ["text": "there"]]]), "hello there")
        XCTAssertNil(AttachmentDetails.transcript(["transcriptSegments": []]))
    }

    func testInkBoundsCropToTheStrokes() {
        let width = 10, height = 8
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for (x, y) in [(3, 2), (6, 5)] { pixels[(y * width + x) * 4] = 0 }
        pixels.withUnsafeBufferPointer { buffer in
            XCTAssertEqual(InkBounds.rect(buffer, width: width, height: height, margin: 1), CGRect(x: 2, y: 1, width: 6, height: 6))
            XCTAssertEqual(InkBounds.rect(buffer, width: width, height: height, margin: 9), CGRect(x: 0, y: 0, width: 10, height: 8),
                           "kept on the page")
        }
        let blank = [UInt8](repeating: 255, count: 16)
        blank.withUnsafeBufferPointer { XCTAssertNil(InkBounds.rect($0, width: 2, height: 2, margin: 0)) }
    }

    // MARK: - A synthetic store

    var folder: URL!

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("journal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    static func rtf(_ string: String) throws -> Data {
        let text = NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        return try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    func makeStore() throws -> URL {
        let url = folder.appendingPathComponent("moments.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        func run(_ sql: String, _ blobs: [Data] = []) {
            var statement: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &statement, nil), SQLITE_OK, sql)
            for (index, blob) in blobs.enumerated() {
                _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, Int32(index + 1), $0.baseAddress, Int32(blob.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            }
            XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE, sql)
            sqlite3_finalize(statement)
        }
        run("CREATE TABLE ZJOURNALMO (Z_PK INTEGER PRIMARY KEY, ZSORTCATEGORY INTEGER, ZSORTORDER INTEGER, ZUSERDELETED INTEGER, ZMERGEABLEATTRIBUTES BLOB)")
        run("CREATE TABLE ZJOURNALENTRYMO (Z_PK INTEGER PRIMARY KEY, ZID BLOB, ZTITLE BLOB, ZTEXT BLOB, ZENTRYDATE REAL, ZCREATEDDATE REAL, ZUPDATEDDATE REAL, ZISDRAFT INTEGER, ZFLAGGED INTEGER, ZRECENTLYDELETED INTEGER, ZISFULLYREMOVED INTEGER)")
        run("CREATE TABLE Z_5JOURNALS (Z_5ENTRIES INTEGER, Z_6JOURNALS INTEGER)")
        run("CREATE TABLE ZJOURNALENTRYASSETMO (Z_PK INTEGER PRIMARY KEY, ZENTRY INTEGER, ZID BLOB, ZASSETTYPE TEXT, ZSOURCE TEXT, ZCREATEDDATE REAL, ZASSETMETADATA BLOB, ZISFULLYREMOVED INTEGER, ZISHIDDEN INTEGER)")
        run("CREATE TABLE ZJOURNALENTRYASSETFILEATTACHMENTMO (Z_PK INTEGER PRIMARY KEY, ZASSET INTEGER, ZINDEX INTEGER, ZFILEPATH TEXT)")
        run("INSERT INTO ZJOURNALMO VALUES (1, -10, 1, 0, NULL)")
        run("INSERT INTO ZJOURNALMO VALUES (2, 0, 0, 0, ?)", [Self.record(["Garden notes", "title", "Mint", "color"])])
        let uuid = Data((0..<16).map(UInt8.init))
        // Entry 1: in the built-in journal, a photo and a map. Entry 2: in Garden notes, newer. Entry 3: deleted.
        run("INSERT INTO ZJOURNALENTRYMO VALUES (1, ?, ?, ?, 800000000, 800000000, NULL, 0, 1, 0, 0)",
            [uuid, try Self.rtf("A day out"), try Self.rtf("We walked to the harbour.")])
        run("INSERT INTO ZJOURNALENTRYMO VALUES (2, ?, ?, ?, 800100000, 800100000, NULL, 1, 0, 0, 0)",
            [Data(repeating: 9, count: 16), try Self.rtf("Seeds"), try Self.rtf("Planted tomatoes.")])
        run("INSERT INTO ZJOURNALENTRYMO VALUES (3, ?, ?, ?, 800200000, 800200000, NULL, 0, 0, 1, 0)",
            [Data(repeating: 7, count: 16), try Self.rtf("Gone"), try Self.rtf("Deleted words.")])
        run("INSERT INTO Z_5JOURNALS VALUES (1, 1), (2, 2), (3, 2)")
        run("INSERT INTO ZJOURNALENTRYASSETMO VALUES (10, 1, ?, 'photo', 'imagePicker', 800000000, ?, 0, 0)",
            [Data(repeating: 3, count: 16), Data([1]) + Data("{}".utf8)])
        run("INSERT INTO ZJOURNALENTRYASSETMO VALUES (11, 1, ?, 'multiPinMap', 'locationPicker', 800000000, ?, 0, 0)",
            [Data(repeating: 4, count: 16), Data([1]) + Data(#"{"visitsData":[{"placeName":"Harbour Café"}]}"#.utf8)])
        run("INSERT INTO ZJOURNALENTRYASSETMO VALUES (12, 1, NULL, 'streakEvent', NULL, NULL, NULL, 0, 0)")
        run("INSERT INTO ZJOURNALENTRYASSETFILEATTACHMENTMO VALUES (1, 10, 0, 'entry/photo/picture.heic')")
        let picture = folder.appendingPathComponent("Attachments/entry/photo/picture.heic")
        try FileManager.default.createDirectory(at: picture.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: picture)
        return url
    }

    func testJournalsAreNamedAndCounted() throws {
        let store = try JournalStore(url: try makeStore())
        let journals = store.journals()
        XCTAssertEqual(journals.map(\.name), ["Journal", "Garden notes"], "the built-in one first, named as the app names it")
        XCTAssertEqual(journals.map(\.entryCount), [1, 1], "a deleted entry is not counted")
        XCTAssertEqual(journals.last?.color, "Mint")
        XCTAssertEqual(journals.first?.isBuiltIn, true)
    }

    func testEntriesReadNewestFirstWithTheirAttachments() throws {
        let store = try JournalStore(url: try makeStore())
        let entries = store.entries()
        XCTAssertEqual(entries.map(\.id), [2, 1], "newest first, Recently Deleted left out")
        let day = try XCTUnwrap(entries.last)
        XCTAssertEqual(day.title, "A day out")
        XCTAssertEqual(day.text, "We walked to the harbour.")
        XCTAssertEqual(day.date, Date(timeIntervalSinceReferenceDate: 800_000_000))
        XCTAssertEqual(day.uuid, "00010203-0405-0607-0809-0A0B0C0D0E0F")
        XCTAssert(day.isBookmarked)
        XCTAssertEqual(day.journals, [1])
        XCTAssertEqual(day.attachments.map(\.kind), ["photo", "multiPinMap"], "streak markers are not attachments")
        XCTAssertEqual(day.attachments.first?.file?.lastPathComponent, "picture.heic")
        XCTAssertEqual(day.attachments.last?.places, ["Harbour Café"])
        XCTAssert(entries.first?.isDraft == true)
        XCTAssertEqual(store.entries(journal: 2).map(\.id), [2])
        XCTAssertEqual(store.entries(includeDeleted: true).map(\.id), [3, 2, 1])
    }

    func testSearchFindsWordsAndPlaces() throws {
        let store = try JournalStore(url: try makeStore())
        XCTAssertEqual(store.search("HARBOUR").map(\.id), [1], "case ignored")
        XCTAssertEqual(store.search("harbour cafe").map(\.id), [1], "accents ignored, places searched")
        XCTAssertEqual(store.search("deleted").map(\.id), [])
        XCTAssertEqual(store.search("deleted", includeDeleted: true).map(\.id), [3])
        XCTAssertEqual(store.search("  ").count, 0)
    }

    func testAMissingStoreAndAMissingEntrySaySo() throws {
        XCTAssertThrowsError(try JournalStore(url: folder.appendingPathComponent("none.sqlite"))) {
            XCTAssertEqual($0 as? AppleJournalError, .storeNotFound(self.folder.appendingPathComponent("none.sqlite")))
        }
        let store = try JournalStore(url: try makeStore())
        XCTAssertThrowsError(try store.entry(id: 99)) { XCTAssertEqual($0 as? AppleJournalError, .entryNotFound(99)) }
        XCTAssertEqual(try store.entry(id: 3).isRecentlyDeleted, true, "an entry by id is found even when deleted")
    }
}
