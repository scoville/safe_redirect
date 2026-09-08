# SafeRedirect

Convenience functions for validating and resolving redirect URLs to prevent
Open Redirect vulnerabilities.

## Installation

Add `safe_redirect` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:safe_redirect, "~> 2.0.0"}
  ]
end
```

This package is tested against the Elixir and OTP versions that are still
supported upstream. Older versions down to the requirement in `mix.exs` may
still work, but they are not covered by CI and not officially supported.

## Open Redirect Vulnerability

If a web application allows an external redirect URL to be set without
proper validation, for example via a `return_to` query parameter, an attacker
can exploit this to redirect users to a phishing or malicious site.

This library allows you to configure a list of known hosts and to validate or
resolve a given redirect URL.

For more information, refer to https://cheatsheetseries.owasp.org/cheatsheets/Unvalidated_Redirects_and_Forwards_Cheat_Sheet.html.

## Server Side Request Forgery Vulnerability

A related but distinct attack vector is Server Side Request Forgery. This
vulnerability occurs when a server makes requests to URLs provided by a user,
for example, when fetching Open Graph data or executing Webhooks. If these
URLs are not validated, an attacker can trick the server into making requests to
the internal network or to the server itself.

To prevent this type of vulnerability, use [ReqSSRF](https://hex.pm/packages/req_ssrf).

For more information, refer to https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html.

## Usage

The allowed redirect URIs can be passed as an option to all library functions,
or you can configure them in the application environment.

The option can either be a list of strings or `URI` structs, a single string or
`URI` struct, or a `{module, function}` tuple that returns such a list.

It is recommended to define the URIs as `URI` structs at compile time to avoid
converting strings to structs each time a redirect URL is validated.

The example below defines a list of hardcoded base URLs in a module attribute.
The URL strings are converted to `URI` structs at compile time. Additionally,
the base URL of the Phoenix endpoint is added to the allowed URIs.

```elixir
defmodule MyAppWeb.RedirectURIs do
  @moduledoc """
  Defines the allowed redirect URIs.

  Used by `SafeRedirect`.
  """

  @allowed_redirect_urls [
    "https://good.example"
  ]

  @spec allowed_redirect_uris() :: [URI.t()]
  def allowed_redirect_uris do
    [
      endpoint_uri()
      | unquote(
          @allowed_redirect_urls
          |> Enum.map(&URI.new!/1)
          |> Macro.escape()
        )
    ]
  end

  defp endpoint_uri do
    URI.new!(MyAppWeb.Endpoint.url())
  end
end
```

You might need to adjust this approach to account for different URIs per
environment.

You can configure this function as the default for all `SafeRedirect`
functions, or you can pass a module/function tuple directly to all functions.

```elixir
config :safe_redirect,
  # you can also set a list of strings or URI structs here
  allowed_redirect_uris: {MyAppWeb.RedirectURIs, :allowed_redirect_uris}
```

With this in place, you can validate whether a given redirect URI is allowed:

```elixir
# If the library is configured via application environment
SafeRedirect.valid_url?("https://good.example/login")

# If the library is not configured via application environment, or to override
# the default
SafeRedirect.valid_url?("https://good.example/login",
  allowed_redirect_uris: {MyAppWeb.RedirectURIs, :allowed_redirect_uris}
)

# Passing the list of allowed URIs directly
SafeRedirect.valid_url?("https://good.example/login",
  allowed_redirect_uris: ["https://good.example"]
)
```

`SafeRedirect.resolve_url/3` returns the given URL if it is allowed,
or a default URL if it is not.

```elixir
iex> SafeRedirect.resolve_url("https://good.example/login")
"https://good.example/login"

iex> SafeRedirect.resolve_url("https://evil.example")
"/"

iex> SafeRedirect.resolve_url("https://evil.example", "/portal")
"/portal"
```

The default value is returned as given and is not validated against the allowed
URIs, so it must not come from user input. This applies to
`SafeRedirect.redirect/4` as well.

Finally, you can use `SafeRedirect.redirect/4` to safely redirect to the given
URL if it is valid or to a default URL if it is not. It works with a `Plug.Conn`
or a LiveView socket. `Plug` and `Phoenix.LiveView` are optional dependencies.

```elixir
SafeRedirect.redirect(conn, "https://good.example/login")

SafeRedirect.redirect(socket, "https://good.example/login")
```

A root-relative path is an internal redirect and an absolute `http` or `https`
URL an external one. For a LiveView socket these are passed to
`Phoenix.LiveView.redirect/2` as `to:` and `external:`; for a `Plug.Conn` both
set the `location` header.

Given a `Plug.Conn`, the connection is halted.

## Validation Rules

- Relative paths starting with `/` are allowed without checking the allowed
  URIs.
- Absolute URLs are allowed if the scheme, host, and port match one of the
  allowed URIs. The scheme and host are compared case-insensitively.
- A trailing dot is part of the host, so `https://good.example.` does not
  match an allowed `https://good.example`.
- Protocol-relative URLs starting with `//` are not allowed.
- A URL with a scheme but no host is not allowed. `mailto:`, `javascript:`,
  and `data:` URLs are always refused.
- Paths must not contain dot segments (`.` or `..`), literal or encoded.
- Paths must not contain control characters, literal or encoded.
- Percent-encoded characters are decoded before a path is checked, so
  `/some%2Fpath` is treated as `/some/path`.
- An allowed URI may not have a path, query string, fragment, or userinfo,
  since only the scheme, host, and port are compared.
