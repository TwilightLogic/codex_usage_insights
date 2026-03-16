import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from .models import ScanResult, ScanWarning, SessionRecord, TokenUsage

DEFAULT_INPUT_PATH = Path.home() / ".codex" / "sessions"


def default_input_path() -> Path:
    return DEFAULT_INPUT_PATH


def discover_session_files(root: Path) -> List[Path]:
    return sorted(path for path in root.rglob("*.jsonl") if path.is_file())


def parse_timestamp(value: object) -> Optional[datetime]:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def parse_usage_payload(payload: object) -> Optional[TokenUsage]:
    if not isinstance(payload, dict):
        return None
    usage = TokenUsage.from_mapping(payload)
    return usage


def parse_session_file(path: Path) -> Tuple[Optional[SessionRecord], List[ScanWarning]]:
    warnings: List[ScanWarning] = []
    session_id = path.stem
    session_timestamp: Optional[datetime] = None
    best_usage: Optional[TokenUsage] = None
    best_event_timestamp: Optional[datetime] = None
    saw_token_count = False
    saw_last_usage_without_total = False

    try:
        with path.open("r", encoding="utf-8") as handle:
            for line_number, raw_line in enumerate(handle, start=1):
                line = raw_line.strip()
                if not line:
                    continue

                try:
                    event = json.loads(line)
                except json.JSONDecodeError as exc:
                    warnings.append(
                        ScanWarning(
                            code="invalid_json_line",
                            message="Invalid JSON line: {message}".format(message=exc.msg),
                            path=str(path),
                            line=line_number,
                        )
                    )
                    continue

                if event.get("type") == "session_meta":
                    payload = event.get("payload", {})
                    if isinstance(payload, dict):
                        session_id = str(payload.get("id") or session_id)
                        session_timestamp = parse_timestamp(payload.get("timestamp")) or parse_timestamp(
                            event.get("timestamp")
                        )

                payload = event.get("payload")
                if not isinstance(payload, dict) or payload.get("type") != "token_count":
                    continue

                saw_token_count = True
                info = payload.get("info")
                if not isinstance(info, dict):
                    continue

                total_usage = parse_usage_payload(info.get("total_token_usage"))
                last_usage = parse_usage_payload(info.get("last_token_usage"))
                event_timestamp = parse_timestamp(event.get("timestamp")) or session_timestamp

                if total_usage is not None and total_usage.is_nonzero() and event_timestamp is not None:
                    is_better = best_usage is None or total_usage.total_tokens > best_usage.total_tokens
                    is_newer_tie = (
                        best_usage is not None
                        and total_usage.total_tokens == best_usage.total_tokens
                        and best_event_timestamp is not None
                        and event_timestamp > best_event_timestamp
                    )
                    if is_better or is_newer_tie:
                        best_usage = total_usage
                        best_event_timestamp = event_timestamp
                elif total_usage is not None and not total_usage.is_nonzero():
                    if last_usage is not None and last_usage.is_nonzero():
                        saw_last_usage_without_total = True

    except OSError as exc:
        warnings.append(
            ScanWarning(
                code="file_read_error",
                message="Failed to read session file: {message}".format(message=str(exc)),
                path=str(path),
            )
        )
        return None, warnings

    if best_usage is None:
        if saw_token_count:
            message = "No usable token_count total_token_usage snapshot found."
            if saw_last_usage_without_total:
                message += " Found last_token_usage data, but no non-zero total_token_usage snapshot."
        else:
            message = "No token_count usage snapshot found in session file."
        warnings.append(
            ScanWarning(
                code="missing_usage_snapshot",
                message=message,
                path=str(path),
            )
        )
        return None, warnings

    # Aggregate sessions by the timestamp of the selected usage snapshot so
    # long-running sessions that cross midnight land in the bucket where their
    # counted usage was actually observed.
    canonical_timestamp = best_event_timestamp or session_timestamp
    if canonical_timestamp is None:
        warnings.append(
            ScanWarning(
                code="missing_timestamp",
                message="Session file had usage data but no usable timestamp.",
                path=str(path),
            )
        )
        return None, warnings

    return (
        SessionRecord(
            session_id=session_id,
            source_path=str(path),
            timestamp_utc=canonical_timestamp,
            usage=best_usage,
        ),
        warnings,
    )


def scan_sessions(root: Path) -> ScanResult:
    root = root.expanduser()
    if not root.exists():
        return ScanResult(
            records=[],
            warnings=[
                ScanWarning(
                    code="input_path_missing",
                    message="Input path does not exist.",
                    path=str(root),
                )
            ],
            scanned_files=0,
            excluded_files=0,
        )

    warnings: List[ScanWarning] = []
    records: List[SessionRecord] = []
    excluded_files = 0
    session_files = discover_session_files(root)

    for path in session_files:
        record, file_warnings = parse_session_file(path)
        warnings.extend(file_warnings)
        if record is None:
            excluded_files += 1
        else:
            records.append(record)

    return ScanResult(
        records=records,
        warnings=warnings,
        scanned_files=len(session_files),
        excluded_files=excluded_files,
    )
