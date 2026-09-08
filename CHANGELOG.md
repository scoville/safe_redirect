# Changelog

This changelog follows the [keep a changelog](https://keepachangelog.com/en/1.1.0/)
format. This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Accept a single string or `URI` struct as `:allowed_redirect_uris`.

### Changed

- Raise `ArgumentError` if invalid options are passed as
  `:allowed_redirect_uris`.
- Raise `ArgumentError` if an unsupported option key is passed.

### Fixed

- Accept percent-encoded paths. `/caf%C3%A9` and `/some%20path` were previously
  rejected, so a redirect target containing a space or a non-ASCII character
  could not be expressed.
- Accept paths with a trailing slash (`/some/path/`) or repeated slashes
  (`/some//path`), which were previously rejected.
- Compare the host case-insensitively, per RFC 3986.
- `SafeRedirect.valid_url?/2` raised `FunctionClauseError` for `nil`. It now
  returns `false`, matching `SafeRedirect.resolve_url/3`.
- `SafeRedirect.redirect/4` raised `UndefinedFunctionError` in applications that
  depend on Plug but not on Phoenix. It now uses `Plug.Conn` directly instead of
  `Phoenix.Controller`.
- Refuse a percent-encoded default value that resolves to a protocol-relative
  URL, such as `/%2F%2Fevil.example` or `/%5Cevil.example`.
- Accept `URI` structs for the URL and the default value in
  `SafeRedirect.redirect/4`.
- Raise `ArgumentError` instead of `CaseClauseError` if the resolved URL cannot
  be redirected to.

## [1.0.2] - 2026-07-30

### Security

- Do not accept protocol-relative URLs with a path.

## [1.0.1] - 2025-10-10

### Fixed

- Type specification of `SafeRedirect.resolve_url/3` didn't allow `nil` as
  default value.

## [1.0.0] - 2025-10-10

Initial release

[Unreleased]: https://github.com/scoville/safe_redirect/compare/1.0.2...HEAD
[1.0.2]: https://github.com/scoville/safe_redirect/compare/1.0.1...1.0.2
[1.0.1]: https://github.com/scoville/safe_redirect/compare/1.0.0...1.0.1
[1.0.0]: https://github.com/scoville/safe_redirect/releases/tag/1.0.0
