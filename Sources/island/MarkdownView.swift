import SwiftUI

/// A lightweight block-level Markdown renderer good enough for plan review: headings,
/// bullet/numbered lists, fenced code blocks, blockquotes, and paragraphs. Inline spans
/// (bold, italic, `code`, links) are handled by Foundation's AttributedString markdown.
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(Self.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    // MARK: Blocks

    enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(String)
        case ordered(index: String, text: String)
        case code(String)
        case quote(String)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case let .heading(level, text):
            inline(text)
                .font(.system(size: [20, 17, 15, 14][min(max(level - 1, 0), 3)], weight: .bold))
                .padding(.top, 2)
        case let .paragraph(text):
            inline(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").font(.system(size: 13)).foregroundStyle(.secondary)
                inline(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            }
        case let .ordered(index, text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(index).font(.system(size: 13).monospacedDigit()).foregroundStyle(.secondary)
                inline(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            }
        case let .code(code):
            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                .textSelection(.enabled)
        case let .quote(text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.2)).frame(width: 2)
                inline(text).font(.system(size: 13)).italic().foregroundStyle(.secondary)
            }
        }
    }

    /// Inline markdown (bold/italic/`code`/links) → styled Text, falling back to plain.
    private func inline(_ s: String) -> Text {
        if let attr = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(s)
    }

    // MARK: Parsing

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var inCode = false
        var codeLines: [String] = []
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph.removeAll()
            }
        }

        for raw in text.components(separatedBy: "\n") {
            let line = raw
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll(); inCode = false
                } else {
                    flushParagraph(); inCode = true
                }
                continue
            }
            if inCode { codeLines.append(line); continue }

            if trimmed.isEmpty { flushParagraph(); continue }

            if let hashes = trimmed.range(of: "^#{1,6} ", options: .regularExpression) {
                flushParagraph()
                let level = trimmed.distance(from: trimmed.startIndex, to: hashes.upperBound) - 1
                blocks.append(.heading(level: level,
                                       text: String(trimmed[hashes.upperBound...])))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                blocks.append(.bullet(String(trimmed.dropFirst(2))))
            } else if let m = trimmed.range(of: "^[0-9]+[.)] ", options: .regularExpression) {
                flushParagraph()
                let idx = String(trimmed[trimmed.startIndex..<m.upperBound]).trimmingCharacters(in: .whitespaces)
                blocks.append(.ordered(index: idx, text: String(trimmed[m.upperBound...])))
            } else if trimmed.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst(2))))
            } else {
                paragraph.append(trimmed)
            }
        }
        if inCode, !codeLines.isEmpty { blocks.append(.code(codeLines.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }
}
