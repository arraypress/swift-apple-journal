//
//  JournalAttachment.swift
//  AppleJournal
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Something added to an entry: a photo, a video, a recording, a map of
/// places, and whatever else Journal lets an entry hold.
public struct JournalAttachment: Sendable, Codable, Equatable {
    /// Its identifier in the store.
    public let id: String
    /// What it is, in Journal's own words: `photo`, `video`, `audio`,
    /// `multiPinMap`, `livePhoto`, `music`…
    public let kind: String
    /// Where it came from: `imagePicker`, `cameraPicker`, `locationPicker`,
    /// `audioPicker`, or a journaling suggestion.
    public let source: String?
    /// When it was added.
    public let added: Date?
    /// Its file on this Mac, when it has one and the file is there.
    public let file: URL?
    /// The places on a map attachment, in order.
    public let places: [String]
    /// What was said in a recording, when Journal transcribed it — or the
    /// words Journal recognised in a sketch's handwriting.
    public let transcript: String?
    /// A sketch's drawing, as PencilKit data: ``JournalDrawing/png(_:scale:)`` draws it.
    public let drawing: Data?

    /// An attachment.
    public init(id: String, kind: String, source: String?, added: Date?, file: URL?, places: [String] = [], transcript: String? = nil,
                drawing: Data? = nil) {
        self.id = id
        self.kind = kind
        self.source = source
        self.added = added
        self.file = file
        self.places = places
        self.transcript = transcript
        self.drawing = drawing
    }
}
