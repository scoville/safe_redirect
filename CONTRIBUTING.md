# Contributing

Thanks for helping out. Issues and pull requests are both welcome.

## Security

Please do not open a public issue for a vulnerability. [SECURITY.md](SECURITY.md)
explains how to report one privately.

## Getting started

```bash
mix deps.get
mix test
```

## Running the checks

Run what CI runs before you push:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test --warnings-as-errors
mix coveralls
mix credo
mix docs --warnings-as-errors
mix dialyzer
```

## Pull requests

For a new feature, or a change to how an existing one behaves, please open an
issue first so we can agree on the shape before you write it. For bug fixes,
documentation and typo fixes, you can open a PR directly.

If an issue exists, reference it in the pull request, for example
`resolves #123`. Add a test that covers the change, and for a bug fix one that
fails without it. Add a changelog entry if the change is user-facing.

Commit messages follow no particular convention. Keep the first line under 72
characters, write it in the present tense, and say what the commit does:
"compare hosts case-insensitively" rather than "compared hosts" or "fixes".
The existing history is a reasonable guide.
