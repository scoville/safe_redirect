# Changelog

This changelog follows the [keep a changelog](https://keepachangelog.com/en/1.1.0/)
format. This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

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
