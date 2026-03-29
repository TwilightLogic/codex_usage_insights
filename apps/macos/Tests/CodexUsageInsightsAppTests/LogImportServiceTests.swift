import Foundation
import Testing
@testable import CodexUsageInsightsApp

struct LogImportServiceTests {
    @Test
    func highestTotalSnapshotCountsOnce() async throws {
        let fixtureDirectory = try makeFixtureDirectory(
            named: [
                "session_with_growth.jsonl"
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let service = LogImportService()
        let result = try await service.importLogs(
            from: fixtureDirectory,
            previousResult: nil,
            progress: { _ in }
        )

        #expect(result.summary.scannedFiles == 1)
        #expect(result.summary.countedSessions == 1)
        #expect(result.summary.usage.inputTokens == 120)
        #expect(result.summary.usage.cachedInputTokens == 80)
        #expect(result.summary.usage.outputTokens == 20)
        #expect(result.summary.usage.reasoningOutputTokens == 10)
        #expect(result.summary.usage.totalTokens == 140)
        #expect(result.segments.count == 2)
        #expect(result.segments.map(\.usage.totalTokens) == [70, 70])
    }

    @Test
    func missingSnapshotsProduceExcludedFilesAndWarnings() async throws {
        let fixtureDirectory = try makeFixtureDirectory(
            named: [
                "session_with_growth.jsonl",
                "session_rate_limit_only.jsonl",
                "session_missing_usage.jsonl"
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let service = LogImportService()
        let result = try await service.importLogs(
            from: fixtureDirectory,
            previousResult: nil,
            progress: { _ in }
        )

        #expect(result.summary.scannedFiles == 3)
        #expect(result.summary.countedSessions == 1)
        #expect(result.summary.excludedFiles == 2)
        #expect(result.summary.warningCount == 4)
    }

    @Test
    func refreshReusesPreviouslyImportedFilesWhenMetadataIsUnchanged() async throws {
        let fixtureDirectory = try makeFixtureDirectory(
            named: [
                "session_with_growth.jsonl"
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let parseRecorder = ParseRecorder()
        let service = LogImportService(
            didParseFile: { url in
                parseRecorder.record(url.path)
            }
        )

        let firstResult = try await service.importLogs(
            from: fixtureDirectory,
            previousResult: nil,
            progress: { _ in }
        )
        let secondResult = try await service.importLogs(
            from: fixtureDirectory,
            previousResult: firstResult,
            progress: { _ in }
        )

        #expect(parseRecorder.count == 1)
        #expect(secondResult.summary.scannedFiles == 1)
        #expect(secondResult.summary.countedSessions == 1)
        #expect(secondResult.summary.usage.totalTokens == firstResult.summary.usage.totalTokens)
        #expect(secondResult.sessions == firstResult.sessions)
        #expect(secondResult.segments == firstResult.segments)
    }

    @Test
    func parserAttributesSegmentsToLatestKnownModelAndPreservesUnknownModel() async throws {
        let fixtureDirectory = try makeFixtureDirectory(
            named: [
                "session_with_model_segments.jsonl",
                "session_with_unknown_model_segments.jsonl"
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let service = LogImportService()
        let result = try await service.importLogs(
            from: fixtureDirectory,
            previousResult: nil,
            progress: { _ in }
        )

        let knownSessionSegments = result.segments
            .filter { $0.sessionID == "session-with-model-segments" }
            .sorted { $0.sequence < $1.sequence }
        let unknownSessionSegments = result.segments
            .filter { $0.sessionID == "session-with-unknown-model-segments" }
            .sorted { $0.sequence < $1.sequence }

        #expect(knownSessionSegments.map(\.model) == ["gpt-5.4", "gpt-5-mini"])
        #expect(knownSessionSegments.map(\.usage.totalTokens) == [35, 50])
        #expect(unknownSessionSegments.map(\.model) == [nil, "gpt-5.4"])
        #expect(unknownSessionSegments.map(\.usage.totalTokens) == [25, 35])
    }

    @Test
    func malformedTailProducesInvalidJsonWarningButKeepsUsableSegments() async throws {
        let fixtureDirectory = try makeFixtureDirectory(
            named: [
                "session_with_invalid_tail.jsonl"
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let service = LogImportService()
        let result = try await service.importLogs(
            from: fixtureDirectory,
            previousResult: nil,
            progress: { _ in }
        )

        #expect(result.summary.countedSessions == 1)
        #expect(result.summary.usage.totalTokens == 95)
        #expect(result.segments.map(\.usage.totalTokens) == [55, 40])
        #expect(result.warnings.contains(where: { $0.code == "invalid_json_line" }))
    }

    private func makeFixtureDirectory(named files: [String]) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        for fileName in files {
            let sourceURL = fixturesRoot().appendingPathComponent(fileName)
            let destinationURL = tempDirectory.appendingPathComponent(fileName)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }

        return tempDirectory
    }

    private func fixturesRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
            .appendingPathComponent("tests", isDirectory: true)
            .appendingPathComponent("fixtures", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }
}

private final class ParseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var parsedPaths: [String] = []

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return parsedPaths.count
    }

    func record(_ path: String) {
        lock.lock()
        parsedPaths.append(path)
        lock.unlock()
    }
}
