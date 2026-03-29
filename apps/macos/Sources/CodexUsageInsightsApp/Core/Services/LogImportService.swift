import Foundation

struct LogImportService: LogImporting {
    private let didParseFile: (@Sendable (URL) -> Void)?

    init(didParseFile: (@Sendable (URL) -> Void)? = nil) {
        self.didParseFile = didParseFile
    }

    func importLogs(
        from directoryURL: URL,
        previousResult: ImportResult?,
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
        var segments: [UsageSegment] = []
        var warnings: [ImportWarning] = []
        var totalUsage = TokenUsage.zero

        let previousImportedFilesByPath = Dictionary(
            uniqueKeysWithValues: (previousResult?.importedFiles ?? []).map { ($0.path, $0) }
        )
        let previousSessionsByPath = Dictionary(
            uniqueKeysWithValues: (previousResult?.sessions ?? []).map { ($0.sourcePath, $0) }
        )
        let previousSegmentsByPath = Dictionary(
            grouping: previousResult?.segments ?? [],
            by: \.sourcePath
        )
        let previousWarningsByPath = Dictionary(
            grouping: previousResult?.warnings ?? [],
            by: \.path
        )

        for (index, fileURL) in logFiles.enumerated() {
            let resourceValues = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey]
            )

            let parseResult: ParsedSessionFile
            if let reusedResult = reusedParsedSessionFile(
                for: fileURL,
                resourceValues: resourceValues,
                previousImportedFilesByPath: previousImportedFilesByPath,
                previousSessionsByPath: previousSessionsByPath,
                previousSegmentsByPath: previousSegmentsByPath,
                previousWarningsByPath: previousWarningsByPath
            ) {
                parseResult = reusedResult
            } else {
                didParseFile?(fileURL)
                parseResult = await parseSessionFile(
                    at: fileURL,
                    resourceValues: resourceValues
                )
            }

            importedFiles.append(parseResult.importedFile)
            segments.append(contentsOf: parseResult.segments)
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

        warnings.append(contentsOf: unsupportedMetricWarnings(for: directoryURL))
        sessions.sort(by: { $0.observedAt > $1.observedAt })

        let summary = UsageOverviewSummary(
            inputPath: directoryURL.path,
            scannedFiles: logFiles.count,
            countedSessions: sessions.count,
            excludedFiles: importedFiles.filter { $0.importStatus != .imported }.count,
            warningCount: warnings.count,
            usage: totalUsage,
            estimatedCostStatus: .unavailable,
            importedAt: Date()
        )

        return ImportResult(
            summary: summary,
            importedFiles: importedFiles,
            sessions: sessions,
            segments: segments.sorted(by: compareSegments),
            warnings: warnings
        )
    }

    private func reusedParsedSessionFile(
        for fileURL: URL,
        resourceValues: URLResourceValues?,
        previousImportedFilesByPath: [String: ImportedFile],
        previousSessionsByPath: [String: UsageSession],
        previousSegmentsByPath: [String: [UsageSegment]],
        previousWarningsByPath: [String: [ImportWarning]]
    ) -> ParsedSessionFile? {
        guard
            let previousImportedFile = previousImportedFilesByPath[fileURL.path],
            previousImportedFile.fileSize == resourceValues?.fileSize.map(Int64.init),
            previousImportedFile.modifiedAt == resourceValues?.contentModificationDate
        else {
            return nil
        }

        return ParsedSessionFile(
            importedFile: previousImportedFile,
            session: previousSessionsByPath[fileURL.path],
            segments: previousSegmentsByPath[fileURL.path]?.sorted(by: compareSegments) ?? [],
            warnings: previousWarningsByPath[fileURL.path] ?? []
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

    private func parseSessionFile(
        at fileURL: URL,
        resourceValues: URLResourceValues?
    ) async -> ParsedSessionFile {
        let baseImportedFile = ImportedFile(
            id: fileURL.path,
            path: fileURL.path,
            fileSize: resourceValues?.fileSize.map(Int64.init),
            modifiedAt: resourceValues?.contentModificationDate,
            importStatus: .imported
        )

        let decoder = JSONDecoder()
        var warnings: [ImportWarning] = []
        var sessionID = fileURL.deletingPathExtension().lastPathComponent
        var sessionTimestamp: Date?
        var workspacePath: String?
        var latestModel: String?
        var bestSnapshot: UsageSnapshot?
        var sawTokenCount = false
        var sawLastUsageWithoutTotal = false
        var sawUsableUsageWithoutTimestamp = false
        var snapshots: [UsageSnapshot] = []
        var lineNumber = 0

        do {
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

                let eventTimestamp = parseTimestamp(event.timestamp) ?? sessionTimestamp

                if event.type == "session_meta", let payload = event.payload {
                    sessionID = payload.id ?? sessionID
                    workspacePath = payload.cwd ?? workspacePath
                    sessionTimestamp = parseTimestamp(payload.timestamp) ?? eventTimestamp
                    continue
                }

                if event.type == "turn_context", let payload = event.payload {
                    latestModel = payload.model ?? latestModel
                    workspacePath = payload.cwd ?? workspacePath
                    continue
                }

                guard let payload = event.payload, payload.type == "token_count" else {
                    continue
                }

                sawTokenCount = true
                let totalUsage = payload.info?.totalTokenUsage
                let lastUsage = payload.info?.lastTokenUsage

                if let totalUsage, totalUsage.isNonZero, let eventTimestamp {
                    let snapshot = UsageSnapshot(
                        timestamp: eventTimestamp,
                        usage: totalUsage,
                        model: latestModel
                    )
                    snapshots.append(snapshot)

                    let shouldReplace =
                        bestSnapshot == nil
                        || totalUsage.totalTokens > (bestSnapshot?.usage.totalTokens ?? 0)
                        || (
                            totalUsage.totalTokens == bestSnapshot?.usage.totalTokens
                            && eventTimestamp > (bestSnapshot?.timestamp ?? .distantPast)
                        )

                    if shouldReplace {
                        bestSnapshot = snapshot
                    }
                } else if let totalUsage, totalUsage.isNonZero {
                    sawUsableUsageWithoutTimestamp = true
                } else if let totalUsage, !totalUsage.isNonZero, let lastUsage, lastUsage.isNonZero {
                    sawLastUsageWithoutTotal = true
                }
            }
        } catch {
            warnings.append(
                ImportWarning(
                    id: "\(fileURL.path):file_read_error",
                    code: "file_read_error",
                    message: "Failed to read session file: \(error.localizedDescription)",
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
                    importStatus: .failed
                ),
                session: nil,
                segments: [],
                warnings: warnings
            )
        }

        guard let bestSnapshot else {
            if sawUsableUsageWithoutTimestamp {
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
                    segments: [],
                    warnings: warnings
                )
            }

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
                segments: [],
                warnings: warnings
            )
        }

        let session = UsageSession(
            id: sessionID,
            sourcePath: fileURL.path,
            workspacePath: workspacePath,
            observedAt: bestSnapshot.timestamp,
            usage: bestSnapshot.usage
        )
        let segments = deriveSegments(
            from: snapshots,
            sessionID: sessionID,
            sourcePath: fileURL.path
        )

        return ParsedSessionFile(
            importedFile: baseImportedFile,
            session: session,
            segments: segments,
            warnings: warnings
        )
    }

    private func deriveSegments(
        from snapshots: [UsageSnapshot],
        sessionID: String,
        sourcePath: String
    ) -> [UsageSegment] {
        let orderedSnapshots = snapshots.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.usage.totalTokens < $1.usage.totalTokens
            }
            return $0.timestamp < $1.timestamp
        }

        var priorCumulative = TokenUsage.zero
        var segments: [UsageSegment] = []

        for (index, snapshot) in orderedSnapshots.enumerated() {
            let delta = snapshot.usage.subtractingClamped(priorCumulative)
            priorCumulative = priorCumulative.componentwiseMax(with: snapshot.usage)

            guard delta.isNonZero else {
                continue
            }

            segments.append(
                UsageSegment(
                    id: "\(sessionID):segment:\(index)",
                    sessionID: sessionID,
                    sourcePath: sourcePath,
                    sequence: index,
                    timestamp: snapshot.timestamp,
                    model: snapshot.model,
                    usage: delta
                )
            )
        }

        return segments
    }

    private func unsupportedMetricWarnings(for directoryURL: URL) -> [ImportWarning] {
        [
            ImportWarning(
                id: "\(directoryURL.path):unsupported_cache_create",
                code: "unsupported_metric",
                message: "Cache create is unavailable in the MVP because local Codex logs do not expose a stable cache-create metric.",
                path: directoryURL.path,
                line: nil
            ),
            ImportWarning(
                id: "\(directoryURL.path):unsupported_billing_block",
                code: "unsupported_metric",
                message: "Billing block analytics are unavailable in the MVP because local Codex logs do not expose a stable provider-native billing unit.",
                path: directoryURL.path,
                line: nil
            )
        ]
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

    private func compareSegments(_ lhs: UsageSegment, _ rhs: UsageSegment) -> Bool {
        if lhs.timestamp == rhs.timestamp {
            return lhs.sequence < rhs.sequence
        }
        return lhs.timestamp < rhs.timestamp
    }
}

private struct ParsedSessionFile {
    let importedFile: ImportedFile
    let session: UsageSession?
    let segments: [UsageSegment]
    let warnings: [ImportWarning]
}

private struct UsageSnapshot {
    let timestamp: Date
    let usage: TokenUsage
    let model: String?
}

private struct LogEvent: Decodable {
    let timestamp: String?
    let type: String
    let payload: Payload?

    struct Payload: Decodable {
        let id: String?
        let timestamp: String?
        let cwd: String?
        let model: String?
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
