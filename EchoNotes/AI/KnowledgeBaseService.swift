import Foundation
import os

/// Scans a folder of markdown files and assembles relevant context for AI summarization.
/// Designed for Obsidian vaults but works with any folder of .md files.
final class KnowledgeBaseService: Sendable {
    private let logger = Logger(subsystem: "com.echonotes", category: "KnowledgeBase")

    /// Maximum characters of assembled context (~2000 tokens at ~4 chars/token).
    private let maxContextChars = 8000

    /// Build context from a knowledge base folder, ranked by relevance to the transcript.
    func buildContext(vaultPath: String, transcript: String) -> String? {
        let vaultURL = URL(fileURLWithPath: (vaultPath as NSString).expandingTildeInPath)

        guard FileManager.default.fileExists(atPath: vaultURL.path) else {
            logger.warning("Knowledge base path does not exist: \(vaultPath)")
            return nil
        }

        // Collect all .md files (skip .obsidian)
        let mdFiles = collectMarkdownFiles(in: vaultURL)
        guard !mdFiles.isEmpty else { return nil }

        // Extract keywords from transcript
        let keywords = extractKeywords(from: transcript)
        guard !keywords.isEmpty else { return nil }

        // Score and rank files
        var scored: [(url: URL, score: Int, content: String)] = []
        for fileURL in mdFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let score = scoreFile(url: fileURL, content: content, keywords: keywords, vaultURL: vaultURL)
            if score > 0 {
                scored.append((fileURL, score, content))
            }
        }

        scored.sort { $0.score > $1.score }

        // Assemble context within budget
        var context = ""
        var charBudget = maxContextChars

        // Always try to include CLAUDE.md or Home.md first (project overview)
        let overviewFiles = scored.filter { url, _, _ in
            let name = url.lastPathComponent.lowercased()
            return name == "claude.md" || name == "home.md"
        }
        let rest = scored.filter { url, _, _ in
            let name = url.lastPathComponent.lowercased()
            return name != "claude.md" && name != "home.md"
        }

        let orderedFiles = overviewFiles + rest

        for (fileURL, _, content) in orderedFiles {
            let relativePath = fileURL.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
            let header = "### \(relativePath)\n"
            // Truncate individual files to keep things balanced
            let maxPerFile = min(2000, charBudget)
            let truncated = content.count > maxPerFile
                ? String(content.prefix(maxPerFile)) + "\n[...truncated]"
                : content
            let entry = header + truncated + "\n\n"

            if entry.count > charBudget { break }
            context += entry
            charBudget -= entry.count
            if charBudget <= 0 { break }
        }

        guard !context.isEmpty else { return nil }

        logger.info("Built knowledge base context: \(context.count) chars from \(min(orderedFiles.count, 10)) files")
        return context
    }

    // MARK: - Private

    private func collectMarkdownFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "md" {
                files.append(fileURL)
            }
        }
        return files
    }

    /// Extract meaningful keywords from the transcript for matching.
    private func extractKeywords(from transcript: String) -> Set<String> {
        // Split into words, lowercase, filter short/common words
        let stopWords: Set<String> = [
            "the", "and", "for", "that", "this", "with", "from", "have", "been",
            "will", "are", "was", "were", "has", "had", "not", "but", "they",
            "you", "your", "our", "can", "would", "could", "should", "about",
            "what", "when", "where", "how", "who", "which", "there", "their",
            "then", "than", "also", "just", "like", "into", "over", "some",
            "yeah", "okay", "right", "going", "think", "know", "want", "need",
            "thing", "things", "really", "actually", "basically", "gonna",
            "got", "get", "one", "two", "three", "it's", "i'm", "we're",
            "don't", "didn't", "that's", "let's", "it'll", "we'll", "i'll",
            "speaker", "unknown"
        ]

        let words = transcript.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }

        // Count frequency and take top keywords
        var freq: [String: Int] = [:]
        for word in words { freq[word, default: 0] += 1 }

        let topKeywords = freq.sorted { $0.value > $1.value }
            .prefix(50)
            .map { $0.key }

        return Set(topKeywords)
    }

    /// Score a file by keyword overlap with the transcript.
    private func scoreFile(url: URL, content: String, keywords: Set<String>, vaultURL: URL) -> Int {
        let lowerContent = content.lowercased()
        let fileName = url.deletingPathExtension().lastPathComponent.lowercased()
        let relativePath = url.path.replacingOccurrences(of: vaultURL.path + "/", with: "").lowercased()

        var score = 0

        // Keyword matches in content
        for keyword in keywords {
            if lowerContent.contains(keyword) {
                score += 1
            }
        }

        // Keyword matches in filename (weighted higher)
        for keyword in keywords {
            if fileName.contains(keyword) {
                score += 5
            }
        }

        // Boost overview/hub files
        if fileName == "claude" || fileName == "home" { score += 10 }
        if fileName.contains("hub") || fileName.contains("overview") { score += 3 }

        // Boost meetings folder (relevant past context)
        if relativePath.hasPrefix("meetings/") { score += 2 }

        // Boost specs (technical context)
        if relativePath.hasPrefix("specs/") { score += 1 }

        return score
    }
}
