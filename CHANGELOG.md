# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Japanese locale: use 登録 (registration) instead of 購読 (subscription) for more natural relay terminology

## [0.0.1] - 2026-04-12

### Added

- ActivityPub relay server with HTTP Signature verification (draft-cavage-http-signatures-06)
- Inbox controller handling Follow, Undo, Create, Announce, Delete, and Update activities
- Pleroma/Akkoma compatibility: accept Follow with relay actor URL as object
- Signed HTTP GET requests for remote actor fetching, enabling compatibility with Mastodon Authorized Fetch (Secure Mode) and Pleroma `authorized_fetch_mode`
- Actor-signer domain validation to prevent activity forgery
- Digest header requirement and conditional Date header validation for POST requests
- Key ID resolution for both fragment-based (`#main-key`) and path-based (`/publickey`) formats
- Shared inbox (`endpoints.sharedInbox`) support for efficient delivery
- Flexible JSON-LD `@context` decoding for mixed arrays (Pleroma format)
- Flexible `actor` field decoding (string or object with `id`)
- Activity deduplication via Redis with atomic SET NX EX and automatic TTL expiration
- Subscriber management with pending/accepted/rejected states and manual accept mode
- Domain blocking and restricted mode (allowlist) support
- Admin REST API with Bearer token authentication
- Admin CLI commands under `APRelay admin`: list-subscribers, accept, reject, block, unblock, list-blocked-domains
- Delivery system with Vapor Queues for reliable activity delivery with exponential backoff retry and smart error classification
- WebFinger, NodeInfo 2.1, and actor endpoint for federation discovery
- RSA-4096 key pair generation and storage
- Prometheus metrics for inbox activities and delivery performance
- Multi-language homepage with English, Korean, and Japanese translations, auto-selected via `Accept-Language` header
- `Localizer` i18n system with JSON translation files and Accept-Language quality factor parsing
- Dark mode support and responsive homepage with status badges, instance grid, and subscriber join dates
- `VersionGeneratorPlugin` build plugin for automatic version and commit detection from git at build time
- `User-Agent` header on outgoing HTTP requests and `Server` response header with relay version info
- Environment variables: `RELAY_URL`, `REDIS_URL`, `ADMIN_TOKEN`, `RELAY_NAME`, `RELAY_DESCRIPTION`, `RELAY_FOOTER`, `MANUAL_ACCEPT`, `RESTRICTED_MODE`, `AP_RELAY_VERSION`, `SOURCE_COMMIT`, `LOG_LEVEL`
- Per-locale environment variable overrides for `RELAY_NAME`, `RELAY_DESCRIPTION`, and `RELAY_FOOTER` (e.g. `RELAY_NAME__KO`)
- GitHub Actions CI/CD: test workflow with swiftly-based Swift toolchain on Ubuntu and macOS, deploy workflow for multi-platform Docker images (amd64/arm64) to GitHub Container Registry
- Docker multi-stage build with jemalloc, static Swift stdlib linking, and non-root user execution
- Docker Compose with Valkey (Redis-compatible) service
- Strict memory safety checking (SE-0458) enabled for all targets
- Comprehensive test suite: inbox integration, signature middleware, admin API, and localization tests

### Security

- Constant-time comparison for admin token authentication via HMAC-based equality
- Unified admin API authentication error responses to prevent configuration state disclosure; all failure cases return identical `401 Unauthorized` with server-side warning logs for operator debugging
