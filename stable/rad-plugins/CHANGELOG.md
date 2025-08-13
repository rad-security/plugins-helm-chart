# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.3.26] - 2026-08-13

### Added

- Ephemeral Volume support for plugins
- Rate limiting for Presidio PII detection
- Enchanced Metrics for easier debugging and monitoring
- Event handler queues are now separated by event type to prevent stalling

### Fixed

- Moved from custom Presidio image to the official Microsoft image
- Open events are now sampled to reduce noise
