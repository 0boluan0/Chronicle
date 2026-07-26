//
//  ManagedMarkdownBlockWriter.swift
//  Chronicle
//

import Foundation

struct ManagedMarkdownBlockWriter {
    enum Error: LocalizedError, Equatable {
        case missingDelimiters(blockID: String)
        case malformedDelimiters(blockID: String)

        var errorDescription: String? {
            UserFacingErrorMessage.message(for: self)
        }
    }

    let blockID: String

    var startMarker: String {
        "<!-- chronicle:managed:start id=\"\(blockID)\" -->"
    }

    var endMarker: String {
        "<!-- chronicle:managed:end id=\"\(blockID)\" -->"
    }

    func createDocument(content: String) -> String {
        renderedBlock(content: content) + "\n"
    }

    func replacingManagedBlock(in existing: String, content: String) throws -> String {
        let markers = existing.topLevelManagedMarkerRanges(
            startMarker: startMarker,
            endMarker: endMarker
        )
        let starts = markers.starts
        let ends = markers.ends

        if starts.isEmpty && ends.isEmpty {
            throw Error.missingDelimiters(blockID: blockID)
        }
        guard starts.count == 1, ends.count == 1,
              let start = starts.first,
              let end = ends.first,
              start.lowerBound < end.lowerBound else {
            throw Error.malformedDelimiters(blockID: blockID)
        }

        var updated = existing
        updated.replaceSubrange(start.lowerBound..<end.upperBound, with: renderedBlock(content: content))
        return updated
    }

    private func renderedBlock(content: String) -> String {
        // User-authored notes can contain arbitrary Markdown. Escape only this block's exact
        // delimiters so content cannot accidentally create a duplicate managed region.
        let normalized = content
            .replacingOccurrences(of: startMarker, with: startMarker.replacingOccurrences(of: "<", with: "&lt;"))
            .replacingOccurrences(of: endMarker, with: endMarker.replacingOccurrences(of: "<", with: "&lt;"))
            .trimmingCharacters(in: .newlines)
        return "\(startMarker)\n\(normalized)\n\(endMarker)"
    }
}

private extension String {
    struct MarkdownFence {
        let marker: Character
        let minimumLength: Int
    }

    func topLevelManagedMarkerRanges(
        startMarker: String,
        endMarker: String
    ) -> (starts: [Range<String.Index>], ends: [Range<String.Index>]) {
        var starts: [Range<String.Index>] = []
        var ends: [Range<String.Index>] = []
        var fence: MarkdownFence?
        var cursor = startIndex

        while cursor < endIndex {
            let lineRange = lineRange(for: cursor..<cursor)
            var contentEnd = lineRange.upperBound
            if contentEnd > lineRange.lowerBound, self[index(before: contentEnd)] == "\n" {
                contentEnd = index(before: contentEnd)
            }
            if contentEnd > lineRange.lowerBound, self[index(before: contentEnd)] == "\r" {
                contentEnd = index(before: contentEnd)
            }
            let contentRange = lineRange.lowerBound..<contentEnd
            let line = String(self[contentRange])

            if let activeFence = fence {
                if line.closesMarkdownFence(activeFence) {
                    fence = nil
                }
            } else if let openedFence = line.openingMarkdownFence() {
                fence = openedFence
            } else if line == startMarker {
                starts.append(contentRange)
            } else if line == endMarker {
                ends.append(contentRange)
            }

            guard lineRange.upperBound > cursor else { break }
            cursor = lineRange.upperBound
        }
        return (starts, ends)
    }

    func openingMarkdownFence() -> MarkdownFence? {
        let candidate = drop(while: { $0 == " " })
        let indentation = distance(from: startIndex, to: candidate.startIndex)
        guard indentation <= 3, let marker = candidate.first, marker == "`" || marker == "~" else {
            return nil
        }
        let length = candidate.prefix(while: { $0 == marker }).count
        guard length >= 3 else { return nil }
        return MarkdownFence(marker: marker, minimumLength: length)
    }

    func closesMarkdownFence(_ fence: MarkdownFence) -> Bool {
        let candidate = drop(while: { $0 == " " })
        let indentation = distance(from: startIndex, to: candidate.startIndex)
        guard indentation <= 3, candidate.first == fence.marker else { return false }
        let runLength = candidate.prefix(while: { $0 == fence.marker }).count
        guard runLength >= fence.minimumLength else { return false }
        return candidate.dropFirst(runLength).allSatisfy { $0 == " " || $0 == "\t" }
    }
}
