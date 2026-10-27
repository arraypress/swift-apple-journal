# Swift Apple Journal

Read Apple Journal from Swift — journals, entries, their words as text or
Markdown, and what was added to them (photos, videos, recordings, maps,
sketches) — by reading Journal's store, not by driving the app.

```swift
import AppleJournal

let store = try JournalStore()
for journal in store.journals() { print(journal.name, journal.entryCount) }
for entry in store.entries() { print(entry.date, entry.title, entry.attachments.map(\.kind)) }
let entry = try store.entry(id: 12)
print(entry.markdown)
store.search("harbour")            // words, map places, recorded and handwritten words

// A sketch, drawn (macOS 26):
if let sketch = entry.attachments.first(where: { $0.kind == "drawing" })?.drawing {
    let png = await JournalDrawing.png(sketch)
}
```

## Where Journal keeps it, and what is there

Measured on macOS 27 with entries written for the purpose:

- **The store** is a Core Data SQLite file in `~/Library/Group Containers/group.com.apple.moments/` —
  "Moments" was Journal's working name. The app's own containers hold only settings and caches.
  It is **not encrypted on the Mac** (end-to-end encryption is iCloud's), but the container is
  protected: the app reading it needs Full Disk Access. It is opened read-only.
- **Titles and words** are RTF. `markdown` keeps bold, italic, strikethrough and list items;
  underline and colour have no Markdown and are dropped, never the words.
- **A journal's name, colour and icon** live in a sync record (`crdt`, a version, then a
  protobuf ending in a table of strings, each value followed by its key). The table is read
  structurally — the run of field-2 strings that ends the record — and a value is taken only
  when a known key follows it. The built-in journal stores no name; it is "Journal".
- **Attachments** are rows with JSON metadata after a one-byte version (`0x01`), and files
  under `Attachments/<entry>/<attachment>/`. Map attachments carry their places; recordings
  may carry a transcript; Journal's streak markers are bookkeeping and left out.
- **Sketches have no file.** They are PaperKit markup (`%PPK…` — PencilKit refuses it as
  malformed) inside the metadata, with the words Journal recognised in the handwriting.
  `JournalDrawing.png` draws one with PaperKit (which counts from the top left — the first
  render was upside down) and crops the page (768 × 1500 points) to its ink.

## Writing

Nothing here writes. Journal has no AppleScript dictionary; its Shortcuts actions can
create an entry (title, text, date, bookmark, location, media) but not choose its journal,
edit or delete one. Writing to the store directly would bypass iCloud's sync — never.

## Tested

9 tests against a synthetic store with the real tables, entries written as RTF the way AppKit
writes it, and a journal record built like the real one byte for byte — no one's journal is
read. Every rule broken on purpose is caught (14 of 14 mutations; one equivalent mutant
removed as dead code). Checked by hand on entries written for the test: two journals, three
entries, five kinds of attachment, a sketch drawn and cropped.

## Requirements

macOS 14 or later (sketches: macOS 26); Swift 6.2. Full Disk Access for the app reading it.

## License

MIT — see [LICENSE](LICENSE).
