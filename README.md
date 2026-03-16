# Codex Usage Analytics

`codex-usage-analytics` is a local CLI for reconstructing Codex Desktop usage from `~/.codex/sessions/**/*.jsonl`, grouping it by day, month, or year, and optionally estimating an API-equivalent dollar cost.

It is intentionally narrow:

- It reads local session logs directly.
- It preserves `input_tokens`, `cached_input_tokens`, `output_tokens`, `reasoning_output_tokens`, and `total_tokens`.
- It renders either a human-readable terminal report or machine-readable JSON.

## What It Helps Answer

Use this tool when you want to answer questions like:

- How many tokens did I use today, this month, or this year?
- How much of that usage came from cached input versus output?
- Which session files were skipped because the logs were incomplete?
- If I apply a selected API pricing profile, what is the rough estimated cost?

## Caveats

This report is reconstructed from local Codex logs. It is not an official ChatGPT or OpenAI billing statement.

If cost estimation is enabled, the dollar figure is only an API-equivalent estimate based on the pricing profile you selected. Local ChatGPT-authenticated Codex usage does not map directly to an official public invoice contract, so treat the cost number as advisory.

Cost estimation interprets `cached_input_tokens` as a priced subset of `input_tokens` and `reasoning_output_tokens` as a reported subset of `output_tokens`. In practice, the estimate bills uncached input, cached input, and output exactly once instead of double-counting overlapping buckets.

## Requirements

- Python 3.9 or newer
- Local Codex Desktop session logs, usually under `~/.codex/sessions`
- No external database or service dependencies

## Install

### Option 1: Run from source

```bash
cd /Users/zibin/Downloads/codex_usage_insights
python3 -m codex_usage_analytics --help
```

### Option 2: Install in editable mode

```bash
cd /Users/zibin/Downloads/codex_usage_insights
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
codex-usage-analytics --help
```

## Quick Start

By default, the CLI reads from:

```bash
~/.codex/sessions
```

Show a daily table report from your local Codex logs:

```bash
python3 -m codex_usage_analytics --period day
```

Show a monthly report as JSON:

```bash
python3 -m codex_usage_analytics --period month --format json
```

Estimate cost with a built-in pricing profile:

```bash
python3 -m codex_usage_analytics --period month --pricing-profile gpt-5.4
```

Use a specific timezone for grouping:

```bash
python3 -m codex_usage_analytics --period day --timezone Asia/Shanghai
```

Use a custom pricing configuration:

```bash
python3 -m codex_usage_analytics \
  --period year \
  --pricing-profile my-custom-profile \
  --pricing-config examples/custom-pricing-profiles.json
```

## Try It Without Real Logs

If you want to confirm the tool works before scanning your own `~/.codex/sessions`, run it against the repository fixture data:

```bash
python3 -m codex_usage_analytics --input-path tests/fixtures/sessions --period day
```

That command should produce a table report with grouped usage totals, warnings for skipped files, and a caveat explaining that the report is reconstructed from local logs.

## CLI Reference

```bash
python3 -m codex_usage_analytics --help
```

Available options:

- `--input-path`: Path to the root session directory. Defaults to `~/.codex/sessions`.
- `--period`: Aggregation period. Supported values are `day`, `month`, and `year`.
- `--timezone`: IANA timezone used for grouping. Defaults to the host system timezone.
- `--pricing-profile`: Name of a built-in or custom pricing profile.
- `--pricing-config`: JSON file that adds or overrides pricing profiles.
- `--format`: Output format, either `table` or `json`.

## Output Formats

### Table Output

The default output is a terminal-friendly table with:

- reporting period
- timezone
- scanned file count
- counted session count
- excluded file count
- per-bucket token totals
- estimated cost status
- warning details for skipped or malformed files

### JSON Output

Use `--format json` to get a structured payload that includes:

- summary token totals
- bucketed token totals
- session counts
- warnings
- pricing metadata
- estimated cost fields

Example:

```bash
python3 -m codex_usage_analytics \
  --input-path tests/fixtures/sessions \
  --period month \
  --format json \
  --pricing-profile gpt-5.4
```

## Pricing Profiles

Pricing profiles are loaded from bundled defaults and can be extended or overridden with `--pricing-config`.

The bundled profiles use this JSON shape:

```json
{
  "profiles": [
    {
      "name": "my-custom-profile",
      "description": "Example profile for local estimates",
      "reviewed_on": "2026-03-16",
      "rates_per_million": {
        "input_tokens": 1.25,
        "cached_input_tokens": 0.125,
        "output_tokens": 10.0
      }
    }
  ]
}
```

In pricing profiles, `input_tokens` means the uncached portion of input after subtracting `cached_input_tokens`. `reasoning_output_tokens` remain visible in reports, but they are treated as part of `output_tokens` for cost estimation rather than billed separately.

Bundled defaults currently include `gpt-5.4` and `gpt-5-mini`, using public OpenAI API pricing reviewed on March 16, 2026. Review them before relying on estimates because public pricing can change.

An example custom file is included at [examples/custom-pricing-profiles.json](/Users/zibin/Downloads/codex_usage_insights/examples/custom-pricing-profiles.json).

## Development

Run the test suite:

```bash
python3 -m unittest discover -s tests -v
```

Run a local smoke test against fixture data:

```bash
python3 -m codex_usage_analytics --input-path tests/fixtures/sessions --period year --pricing-profile gpt-5-mini
```

## Limitations

- The parser uses the highest observed `total_token_usage` snapshot per session file instead of summing every incremental event.
- Files without a usable `total_token_usage` snapshot are excluded from totals and surfaced as warnings.
- Truncated or malformed JSONL files may lead to partial results; the tool continues when possible and records warnings.
- The first version only supports local Codex session logs and a CLI or JSON reporting surface.

Compared with adjacent tools:

- `ccusage` validates the general local-log approach and offers broader usage and cost reporting across coding tools.
- `codex-ratelimit` focuses on rate-limit windows instead of calendar rollups.
- SessionWatcher targets broader real-time monitoring instead of a narrow historical reporting workflow.
