# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- LitePub mutual follow support: relay sends Follow back to instances that follow the relay actor directly, and handles Accept/Reject responses
- Relay support for Move, Add, Remove, and Undo (non-Follow) activity types
- Relay support for Like and EmojiReact activity types
- Periodic instance info fetching for subscriber instances with software name/version, registration status, staff accounts, reachability, and favicon displayed on the homepage
- `INSTANCE_INFO_CHECK_INTERVAL` environment variable to configure instance info check frequency (default: 300 seconds, minimum: 60)
- `ALLOWED_PRIVATE_ADDRESSES` environment variable to whitelist private IP CIDR ranges for internal/test cluster deployments
- `DEFAULT_QUEUE_WORKER_COUNT` and `DELIVERY_QUEUE_WORKER_COUNT` environment variables for configurable queue worker counts
- `SOURCE_REPOSITORY_URL` and `SOURCE_REPOSITORY_COMMIT_PATH` environment variables for configurable source repository links

### Changed

- Homepage instance list now displays subscribers in join order instead of alphabetical order
- Prometheus metrics endpoint moved to a dedicated server controlled by `METRICS_BIND` environment variable
- Delivery jobs now run on a dedicated queue separate from the default job queue
- Japanese locale: use 登録 (registration) instead of 購読 (subscription) for more natural relay terminology

### Fixed

- NodeInfo response now includes required `services` field and uses free-form `metadata` per NodeInfo 2.1 schema
- Homepage now shows subscriber instance details immediately after server boot instead of waiting for the first scheduled check
- InstanceInfoFetchJob error logs now include the failing domain name for diagnosis

### Security

- Validate outbound URLs in instance info fetch to prevent SSRF via crafted `link.href` (scheme, reserved hostname, and private IP literal checks)

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
