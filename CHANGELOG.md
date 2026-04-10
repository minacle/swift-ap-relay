# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Refactor DeliveryService to AsyncStream-based work queue with structured concurrency and graceful shutdown via Vapor LifecycleHandler
- Use constant-time comparison for admin token authentication via SHA256 digest equality

### Fixed

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
- Activity deduplication via LRU cache with TTL
- Subscriber management with pending/accepted/rejected states and manual accept mode
- Domain blocking and restricted mode (allowlist) support
- Admin REST API with Bearer token authentication
- Admin CLI commands: list-subscribers, accept, reject, block, unblock
- Delivery service with exponential backoff retry and smart error classification
- WebFinger, NodeInfo 2.1, and actor endpoint for federation discovery
- RSA-4096 key pair generation and database storage
- Prometheus metrics for inbox activities and delivery performance
- Docker and docker-compose support
- SQLite and PostgreSQL database support via Fluent
- Comprehensive test suite: inbox integration, signature middleware, and admin API tests
