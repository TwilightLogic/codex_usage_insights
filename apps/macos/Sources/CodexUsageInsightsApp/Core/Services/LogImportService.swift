import Foundation

struct LogImportService: LogImporting {

    func importLogs(
        from directoryURL: URL,
        progress: @escaping @Sendable (ImportProgress) -> Void
    ) async throws -> ImportResult {
        guard directoryExists(at: directoryURL) else {
            throw LogImportError.invalidDirectory(directoryURL.path)
        }

        let logFiles = discoverLogFiles(at: directoryURL)
        progress(
            ImportProgress(
                totalFiles: logFiles.count,
                processedFiles: 0,
                countedSessions: 0,
                warningCount: 0
            )
        )

        var importedFiles: [ImportedFile] = []
        var sessions: [UsageSession] = []
        var warnings: [ImportWarning] = []
        var totalUsage = TokenUsage.zero

        for (index, fileURL) in logFiles.enumerated() {
            let parseResult = try await parseSessionFile(at: fileURL)
            importedFiles.append(parseResult.importedFile)
            warnings.append(contentsOf: parseResult.warnings)

            if let session = parseResult.session {
                sessions.append(session)
                totalUsage = totalUsage.adding(session.usage)
            }

            progress(
                ImportProgress(
                    totalFiles: logFiles.count,
                    processedFiles: index + 1,
                    countedSessions: sessions.count,
                    warningCount: warnings.count
                )
            )
        }

        sessions.sort(by: { $0.observedAt > $1.observedAt })

        let summary = UsageOverviewSummary(
            inputPath: directoryURL.path,
            scannedFiles: logFiles.count,
            countedSessions: sessions.count,
            excludedFiles: max(logFiles.count - sessions.count, 0),
            warningCount: warnings.count,
            usage: totalUsage,
            estimatedCostStatus: .unavailable,
            importedAt: Date()
        )

        return ImportResult(
            summary: summary,
            importedFiles: importedFiles,
            sessions: sessions,
            warnings: warnings
        )
    }

    private func directoryExists(at directoryURL: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func discoverLogFiles(at directoryURL: URL) -> [URL] {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var logFiles: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "jsonl" {
                logFiles.append(url)
            }
        }

        return logFiles.sorted(by: { $0.path < $1.path })
    }

    private func parseSessionFile(at fileURL: URL) async throws -> ParsedSessionFile {
        let decoder = JSONDecoder()
        let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let baseImportedFile = ImportedFile(
            id: fileURL.path,
            path: fileURL.path,
            fileSize: resourceValues?.fileSize.map(Int64.init),
            modifiedAt: resourceValues?.contentModificationDate,
            importStatus: .imported
        )

        var warnings: [ImportWarning] = []
        var sessionID = fileURL.deletingPathExtension().lastPathComponent
        var sessionTimestamp: Date?
        var workspacePath: String?
        var bestUsage: TokenUsage?
        var bestEventTimestamp: Date?
        var sawTokenCount = false
        var sawLastUsageWithoutTotal = false
        var lineNumber = 0

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        for try await line in handle.bytes.lines {
            lineNumber += 1
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            let event: LogEvent
            do {
                event = try decoder.decode(LogEvent.self, from: Data(trimmed.utf8))
            } catch {
                warnings.append(
                    ImportWarning(
                        id: "\(fileURL.path):\(lineNumber):invalid_json_line",
                        code: "invalid_json_line",
                        message: "Invalid JSON line: \(error.localizedDescription)",
                        path: fileURL.path,
                        line: lineNumber
                    )
                )
                continue
            }

            if event.type == "session_meta", let payload = event.payload {
                sessionID = payload.id ?? sessionID
                workspacePath = payload.cwd ?? workspacePath
                sessionTimestamp = parseTimestamp(payload.timestamp) ?? parseTimestamp(event.timestamp)
            }

            guard let payload = event.payload, payload.type == "token_count" else {
                continue
            }

            sawTokenCount = true
            let totalUsage = payload.info?.totalTokenUsage
            let lastUsage = payload.info?.lastTokenUsage
            let eventTimestamp = parseTimestamp(event.timestamp) ?? sessionTimestamp

            if let totalUsage, totalUsage.isNonZero, let eventTimestamp {
                let shouldReplace =
                    bestUsage == nil
                    || totalUsage.totalTokens > (bestUsage?.totalTokens ?? 0)
                    || (
                        totalUsage.totalTokens == bestUsage?.totalTokens
                        && eventTimestamp > (bestEventTimestamp ?? .distantPast)
                    )

                if shouldReplace {
                    bestUsage = totalUsage
                    bestEventTimestamp = eventTimestamp
                }
            } else if let totalUsage, !totalUsage.isNonZero, let lastUsage, lastUsage.isNonZero {
                sawLastUsageWithoutTotal = true
            }
        }

        guard let usage = bestUsage else {
            let message: String
            if sawTokenCount {
                if sawLastUsageWithoutTotal {
                    message = "No usable token_count total_token_usage snapshot found. Found last_token_usage data, but no non-zero total_token_usage snapshot."
                } else {
                    message = "No usable token_count total_token_usage snapshot found."
                }
            } else {
                message = "No token_count usage snapshot found in session file."
            }

            warnings.append(
                ImportWarning(
                    id: "\(fileURL.path):missing_usage_snapshot",
                    code: "missing_usage_snapshot",
                    message: message,
                    path: fileURL.path,
                    line: nil
                )
            )

            return ParsedSessionFile(
                importedFile: ImportedFile(
                    id: baseImportedFile.id,
                    path: baseImportedFile.path,
                    fileSize: baseImportedFile.fileSize,
                    modifiedAt: baseImportedFile.modifiedAt,
                    importStatus: .excluded
                ),
                session: nil,
                warnings: warnings
            )
        }

        guard let observedAt = bestEventTimestamp ?? sessionTimestamp else {
            warnings.append(
                ImportWarning(
                    id: "\(fileURL.path):missing_timestamp",
                    code: "missing_timestamp",
                    message: "Session file had usage data but no usable timestamp.",
                    path: fileURL.path,
                    line: nil
                )
            )

            return ParsedSessionFile(
                importedFile: ImportedFile(
                    id: baseImportedFile.id,
                    path: baseImportedFile.path,
                    fileSize: baseImportedFile.fileSize,
                    modifiedAt: baseImportedFile.modifiedAt,
                    importStatus: .excluded
                ),
                session: nil,
                warnings: warnings
            )
        }

        return ParsedSessionFile(
            importedFile: baseImportedFile,
            session: UsageSession(
                id: sessionID,
                sourcePath: fileURL.path,
                workspacePath: workspacePath,
                observedAt: observedAt,
                usage: usage
            ),
            warnings: warnings
        )
    }

    private func parseTimestamp(_ rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        let fractionalTimestampFormatter = ISO8601DateFormatter()
        fractionalTimestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalTimestampFormatter.date(from: rawValue) {
            return date
        }

        let standardTimestampFormatter = ISO8601DateFormatter()
        standardTimestampFormatter.formatOptions = [.withInternetDateTime]
        return standardTimestampFormatter.date(from: rawValue)
    }
}

private struct ParsedSessionFile {
    let importedFile: ImportedFile
    let session: UsageSession?
    let warnings: [ImportWarning]
}

private struct LogEvent: Decodable {
    let timestamp: String?
    let type: String
    let payload: Payload?

    struct Payload: Decodable {
        let id: String?
        let timestamp: String?
        let cwd: String?
        let type: String?
        let info: TokenInfo?
    }

    struct TokenInfo: Decodable {
        let totalTokenUsage: TokenUsage?
        let lastTokenUsage: TokenUsage?

        enum CodingKeys: String, CodingKey {
            case totalTokenUsage = "total_token_usage"
            case lastTokenUsage = "last_token_usage"
        }
    }
}

private enum LogImportError: LocalizedError {
    case invalidDirectory(String)

    var errorDescription: String? {
        switch self {
        case .invalidDirectory(let path):
            return "The selected directory does not exist or is not a folder: \(path)"
        }
    }
}
