# Changelog

## 2026-08-09

- Fixed Claude OAuth credential reads by using the native macOS Keychain API without a short subprocess timeout.
- Matched plan usage labels and percentages to Claude's Current session and All models values.
- Added request throttling and HTTP 429 backoff for live plan usage.
- Preserved the last live weekly value and represented an exhausted session as 100% used until its server-provided reset time.
- Stopped local transcript totals from being shown as plan utilization when live usage is unavailable.
