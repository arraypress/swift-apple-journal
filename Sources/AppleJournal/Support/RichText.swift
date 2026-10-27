//
//  RichText.swift
//  AppleJournal
//
//  Created by David Sherlock on 2026.
//
//  An entry's title and body are RTF. This reads them as plain text and as
//  Markdown: bold, italic and strikethrough runs marked, list paragraphs
//  given `- ` or `1. `. Underline and colour have no Markdown and are
//  dropped; the words never are.
//

import AppKit
import Foundation

enum RichText {

    /// The attributed text in RTF data, or nil when it is not RTF.
    static func attributed(_ data: Data) -> NSAttributedString? {
        try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
    }

    /// Plain text, trimmed.
    static func plain(_ data: Data?) -> String {
        guard let data, let text = attributed(data) else { return "" }
        return text.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Markdown, paragraph by paragraph.
    static func markdown(_ data: Data?) -> String {
        guard let data, let text = attributed(data) else { return "" }
        var lines: [String] = []
        var number = 0
        let whole = text.string as NSString
        whole.enumerateSubstrings(in: NSRange(location: 0, length: whole.length), options: .byParagraphs) { _, range, _, _ in
            let style = range.length > 0 ? text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle : nil
            var line = runs(text, in: range)
            if let list = style?.textLists.last {
                let ordered = list.markerFormat.rawValue.contains("decimal") || list.markerFormat.rawValue.contains("roman")
                number = ordered ? number + 1 : 0
                line = (ordered ? "\(number). " : "- ") + line
            } else {
                number = 0
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A paragraph's runs with their emphasis marked.
    static func runs(_ text: NSAttributedString, in range: NSRange) -> String {
        var out = ""
        text.enumerateAttributes(in: range) { attributes, runRange, _ in
            let words = (text.string as NSString).substring(with: runRange)
            let traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            let struck = ((attributes[.strikethroughStyle] as? Int) ?? 0) != 0
            out += marked(words, bold: traits.contains(.bold), italic: traits.contains(.italic), struck: struck)
        }
        return out
    }

    /// Words wrapped in Markdown's marks, outside any spaces at their edges
    /// (`** bold**` is not bold in Markdown).
    static func marked(_ words: String, bold: Bool, italic: Bool, struck: Bool) -> String {
        let core = words.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty, bold || italic || struck else { return words }
        let lead = String(words.prefix { $0 == " " }), trail = String(words.reversed().prefix { $0 == " " })
        var marks = ""
        if bold { marks += "**" }
        if italic { marks += "_" }
        if struck { marks += "~~" }
        return lead + marks + core + String(marks.reversed()) + trail
    }
}
