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
        let result = try await service.importLogs(from: fixtureDirectory, progress: { _ in })

        #expect(result.summary.scannedFiles == 1)
        #expect(result.summary.countedSessions == 1)
        #expect(result.summary.usage.inputTokens == 120)
        #expect(result.summary.usage.cachedInputTokens == 80)
        #expect(result.summary.usage.outputTokens == 20)
        #expect(result.summary.usage.reasoningOutputTokens == 10)
        #expect(result.summary.usage.totalTokens == 140)
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
        let result = try await service.importLogs(from: fixtureDirectory, progress: { _ in })

        #expect(result.summary.scannedFiles == 3)
        #expect(result.summary.countedSessions == 1)
        #expect(result.summary.excludedFiles == 2)
        #expect(result.summary.warningCount == 2)
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
