# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `.dockerignore` symlink to `.gitignore` to exclude unnecessary files from Docker build context

### Changed

- Relicense project from AGPL-3.0 to Apache License 2.0

### Added

- Project README with feature overview, build/run instructions, Docker guide, environment variables reference, and admin CLI documentation
- `admin` command group: admin CLI commands (`accept`, `reject`, `block`, `unblock`, `list-subscribers`, `list-blocked-domains`) are now subcommands under `APRelay admin` instead of top-level commands
- Signed HTTP GET requests for remote actor fetching, enabling compatibility with Mastodon Authorized Fetch (Secure Mode) and Pleroma `authorized_fetch_mode`
- `HTTPSignature.signGET()` method for signing GET requests with `(request-target)`, `host`, and `date` headers
- Strict memory safety checking (SE-0458) enabled for all targets via `.strictMemorySafety()` swift setting
- GitHub Actions deploy workflow for multi-platform Docker image builds (amd64/arm64) pushed to GitHub Container Registry
- GitHub Actions test workflow with swiftly-based Swift toolchain management across Ubuntu and macOS runners
- `.swift-version` file for consistent Swift toolchain pinning via swiftly
- AdminConnection struct for CLI admin commands to specify custom API endpoint via `--url`, `--hostname`, `--port`, `--tls`, or `--unix-socket` flags
- Leaf templating engine for server-side HTML rendering with `index.leaf` template
- RelayRepository protocol with RedisRelayRepository implementation for Redis-backed data access
- Vapor Queues job system with DeliveryJob, AcceptJob, and RejectJob for reliable activity delivery
- SignedDeliveryHelper for shared HTTP Signature signing across all delivery jobs
- MockRelayRepository actor for in-memory testing without Redis
- Valkey (Redis-compatible) service in docker-compose with AOF persistence

### Changed

- Batch Redis hash lookups in `getAllSubscribers`, `getAcceptedInboxURLs`, and `getAllBlockedDomains` using `EventLoopFuture.whenAllSucceed` to eliminate N+1 sequential round-trips
- Narrow APRelayCore access control from `public` to `package` since all consumers are within the same Swift package
- Restructure logging levels for relay operations: subscription state changes (follow, unfollow, accept, reject) use `notice`, routine operations and security-audit traces (received, delivered, duplicate, non-subscriber, unsupported type) use `info`
- Add missing logs to `handleForward` for non-subscriber rejection and successful forwarding
- `HTTPSignature.verify()` no longer accepts an unused `body` parameter
- Actor fetch Accept header now uses spec-compliant `application/ld+json; profile="https://www.w3.org/ns/activitystreams"` with `application/activity+json` fallback
- Replace `ISO8601DateFormatter` with `Date.ISO8601FormatStyle` in RedisRelayRepository, removing `nonisolated(unsafe)` static property
- Replace `@unchecked Sendable` on `RedisRelayRepository` and `RedisActivityDeduplicator` with compiler-verified `Sendable` by storing `any RedisClient & Sendable` (backed by vapor/redis `Application.Redis`)
- Mark `@preconcurrency import RediStack` with `@unsafe` to acknowledge memory safety implications under strict checking
- Replace inline HTML generation in IndexController with Leaf template rendering
- Rewrite Dockerfile to follow Vapor recommended template with jemalloc, build caching, non-root user, and resource staging
- Remove Redis MULTI/EXEC transaction wrapping from subscriber save and delete operations
- Replace Fluent ORM (SQLite/PostgreSQL) with Redis as the sole data store
- Replace custom AsyncStream-based DeliveryService with Vapor Queues for persistent, concurrency-controlled delivery
- Broadcast delivery now dispatches individual jobs per inbox, with concurrency naturally limited by queue workerCount
- Models are now plain Codable structs instead of Fluent Model classes
- Environment variable `DATABASE_URL` replaced by `REDIS_URL` (default: `redis://localhost:6379`)
- Docker Compose uses Valkey 8 instead of a relational database
- Consolidate `RELAY_DOMAIN`, `RELAY_SCHEME`, `RELAY_HOST`, `RELAY_PORT` into single `RELAY_URL` environment variable
- Refactor admin CLI commands (accept, reject, block, unblock, list-subscribers) to use Admin REST API client instead of direct database access
- Use constant-time comparison for admin token authentication via HMAC-based equality (replacing SHA256 digest comparison)
- Skip Redis connection and signing key initialization for non-serve commands (`admin`, `--help`), so CLI commands work without a running Redis instance
- `RELAY_URL` in docker-compose now defaults to `http://127.0.0.1:8080` instead of requiring the variable to be set
- Deploy workflow uses native ARM64 runners (`ubuntu-24.04-arm`) for arm64 Docker builds instead of QEMU emulation
- Deploy workflow migrated to `docker/github-builder` reusable workflow for simplified multi-platform build, digest management, and manifest merging

### Removed

- In-memory ActivityDeduplicator actor and `swift-collections` dependency (replaced by Redis-backed deduplication)
- `RELAY_DOMAIN`, `RELAY_SCHEME`, `RELAY_HOST`, `RELAY_PORT` environment variables (replaced by `RELAY_URL`)
- Manual HTTP server hostname/port configuration from `configure.swift`
- Fluent ORM, SQLite driver, and PostgreSQL driver dependencies
- All database migration files
- DeliveryService actor with in-memory AsyncStream work queue

### Security

- Unify admin API authentication error responses to prevent configuration state disclosure; all failure cases (token not set, missing header, invalid token) now return identical `401 Unauthorized` with server-side warning logs for operator debugging

### Fixed

- Fix inaccurate subscriber count in relay/forward log messages when sender's inbox URL is not in the subscriber list
- Fix flaky CI tests caused by `setenv()` race condition across concurrent test suites; replace process-global environment variables with direct `RelayConfiguration` injection per test app instance
- Fix digest mismatch (401) on incoming POST requests by explicitly collecting the request body in signature verification middleware; Vapor's route-level body collection runs after middleware, so `request.body.data` was nil for streamed requests
- Fix crash on startup when Redis connection pools are not yet available during `configure()` by deferring signing key initialization to lifecycle boot hook
- Replace `try!` with `throws` in HTTP signature signing to prevent server crashes
- Add error logging for fire-and-forget delivery tasks (Accept/Reject) that previously swallowed errors silently
- Remove redundant database query in activity forwarding by reusing initial subscriber lookup
- Change Subscriber model `state` property from `@Enum` to `@Field` to match string-typed migration and ensure PostgreSQL compatibility

### Added

- ActivityPub relay server with HTTP Signature verification (draft-cavage-http-signatures-06)
- Inbox controller handling Follow, Undo, Create, Announce, Delete, and Update activities
- Pleroma/Akkoma compatibility: accept Follow with relay actor URL as object
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
- Admin CLI commands: list-subscribers, accept, reject, block, unblock, list-blocked-domains
- AdminAPIClient HTTP client for admin CLI commands to communicate with the relay server via REST API
- Delivery service with exponential backoff retry and smart error classification
- WebFinger, NodeInfo 2.1, and actor endpoint for federation discovery
- RSA-4096 key pair generation and storage
- Prometheus metrics for inbox activities and delivery performance
- Docker and docker-compose support
- Comprehensive test suite: inbox integration, signature middleware, and admin API tests
