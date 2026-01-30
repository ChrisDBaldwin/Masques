# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.2] - 2026-01-30

### Changed
- Spinner verb format updated to `Masque:Verb` style (e.g., `Mirror:Reflecting`)

## [0.3.1] - 2026-01-30

### Fixed
- Marketplace name registration

## [0.3.0] - 2026-01-30

### Added
- Spinner verbs (spinnerVerbs) for custom activity indicators during masque sessions
- Automatic spinner verb injection when donning masques
- Spinner verb cleanup when doffing masques

## [0.2.0] - 2026-01-26

### Added
- Manifest-based masque listing for fast lookups
- `/sync-manifest` command to regenerate manifest files
- Private masques support via `~/.masques/` directory
- Evaluation suites for masque behavior validation

### Changed
- `/list` now reads from manifest files instead of scanning all masque files
- Improved masque discovery with dual-path (private + shared) loading

## [0.1.0] - 2026-01-22

### Added
- Initial release
- Core masque schema with five components: intent, context, knowledge, access, lens
- `/don`, `/doff`, `/id`, `/list`, `/inspect` commands
- Four bundled masques: Codesmith, Chartwright, Firekeeper, Mirror
- Session state persistence in `.claude/masques.local.md`
- MCP server bundling support in masque definitions
