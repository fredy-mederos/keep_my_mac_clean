import CleanerCore
import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One-line suggestions for your own files ("My files"), written by Apple's on-device model.
///
/// The model only writes text. It never changes an item's tier or what cleaning does, and
/// everything falls back to the fixed suggestion when the model is off or unavailable.
@MainActor
@Observable
final class SmartSuggestions {
    enum Availability: Equatable {
        case available
        case unavailable(String)
    }

    private(set) var texts: [String: String]
    private var pending: [CleanupItem] = []
    private var inFlight = Set<String>()
    private var isWorking = false
    private let cache = SuggestionCache()

    init() {
        texts = cache.load()
    }

    static var availability: Availability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable("This Mac doesn't support Apple Intelligence.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("Turn on Apple Intelligence in System Settings to use this.")
            case .unavailable(.modelNotReady):
                return .unavailable("The on-device model is still downloading. Try again later.")
            case .unavailable:
                return .unavailable("The on-device model isn't available right now.")
            }
        }
        #endif
        return .unavailable("Needs macOS 26 or later with Apple Intelligence.")
    }

    /// Cached suggestion for this exact file (same path, size and date).
    func text(for item: CleanupItem) -> String? {
        texts[Self.key(for: item)]
    }

    /// Queues a suggestion for one of your files, or a one-liner for a project with a long or
    /// non-English description, unless it's cached or already queued.
    func request(_ item: CleanupItem) {
        let wanted = item.safety == .personal || item.project?.wantsModelSummary == true
        guard wanted, Self.availability == .available else { return }
        let key = Self.key(for: item)
        guard texts[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)
        pending.append(item)
        processNext()
    }

    /// One at a time: the on-device model is shared and quick enough sequentially.
    private func processNext() {
        guard !isWorking, !pending.isEmpty else { return }
        isWorking = true
        let item = pending.removeFirst()
        Task {
            if let text = await Self.generate(for: item) {
                texts[Self.key(for: item)] = text
                cache.save(texts)
            }
            inFlight.remove(Self.key(for: item))
            isWorking = false
            processNext()
        }
    }

    static func key(for item: CleanupItem) -> String {
        if let project = item.project {
            // A project's line only changes when its description does.
            return "project|\(item.id)|\(stableHash(project.description ?? ""))"
        }
        return "\(item.id)|\(item.size)|\(Int(item.lastUsed?.timeIntervalSince1970 ?? 0))"
    }

    /// FNV-1a, stable across launches (unlike `hashValue`).
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// The facts the model sees. Nothing but the file's metadata, and it stays on this Mac.
    static func facts(for item: CleanupItem) -> String {
        var lines = [
            "File name: \(item.title)",
            "Type and folder: \(item.detail ?? "unknown")",
            "Size: \(ByteFormat.standard(item.size))",
        ]
        if let date = item.lastUsed {
            lines.append("Last \(item.dateKind.label): \(date.formatted(.relative(presentation: .named))) (\(date.formatted(date: .abbreviated, time: .omitted)))")
        }
        if let reason = item.reason {
            lines.append("Generic advice for this type of file: \(reason)")
        }
        return lines.joined(separator: "\n")
    }

    private static func generate(for item: CleanupItem) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if let project = item.project {
                return try? await ProjectBlurbWriter.write(facts: project.prompt)
            }
            return try? await SuggestionWriter.write(facts: facts(for: item))
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct FileSuggestion {
    @Guide(description: "One practical sentence of at most 20 words: keep, move to external or cloud storage, or remove the file, and why.")
    var suggestion: String
}

@available(macOS 26.0, *)
enum SuggestionWriter {
    static let instructions = """
        You help someone free disk space on their Mac. You get facts about one of their own files: \
        its name, type, folder, size and dates. Write one short, practical suggestion: keep it, move it \
        to an external drive or cloud storage, or remove it, and say why. Use only the facts given and \
        never guess what's inside the file. No quotes, no emoji.
        """

    static func write(facts: String) async throws -> String? {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: facts, generating: FileSuggestion.self)
        let text = response.content.suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(200))
    }
}
#endif

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct ProjectBlurb {
    @Guide(description: "What the project is, as a noun phrase of at most 12 words, in English")
    var description: String
}

@available(macOS 26.0, *)
enum ProjectBlurbWriter {
    static let instructions = """
        You describe a developer's code project in one short line, in English, from the facts given. \
        Say what it is or does, not how active it is. Don't mention dates or maintenance. \
        No quotes, no emoji.
        """
    /// Longer answers are dropped in favor of the plain line.
    static let maximumWords = 20

    static func write(facts: String) async throws -> String? {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: facts, generating: ProjectBlurb.self)
        let text = response.content.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.split(separator: " ").count <= maximumWords else { return nil }
        return text
    }
}
#endif

/// Suggestions survive relaunches so the model runs once per file.
private struct SuggestionCache {
    let fileURL = SettingsStore.defaultURL.deletingLastPathComponent().appendingPathComponent("suggestions.json")
    static let maxEntries = 500

    func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    func save(_ texts: [String: String]) {
        var trimmed = texts
        if trimmed.count > Self.maxEntries {
            for key in trimmed.keys.sorted().prefix(trimmed.count - Self.maxEntries) { trimmed.removeValue(forKey: key) }
        }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(trimmed).write(to: fileURL, options: .atomic)
    }
}
