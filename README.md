# SafeRedirect

Convenience functions for validating and resolving redirect URLs to prevent
Open Redirect vulnerabilities.

## Installation

Add `safe_redirect` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:safe_redirect, "~> 1.0.2", organization: "scoville"}
  ]
end
```

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

To prevent this type of vulnerability, use [Safeurl](https://hex.pm/packages/safeurl).

For more information, refer to https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html.

## Usage

The allowed redirect URIs can be passed as an option to all library functions,
or you can configure them in the application environment.

The option can either be a list of strings or `URI` structs, or it can be a
`{module, function}` tuple that returns such a list.

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

Finally, you can use `safe_redirect/4` to safely redirect to the given URL if
it is valid or to a default URL if it is not. The function automatically sets
the `to` or `external` option depending on whether the resolved URL is relative
or absolute. It works both with LiveView sockets and `Plug.Conn` structs,
provided that `Plug` and `Phoenix.LiveView` are among your application's
dependencies.

```elixir
SafeRedirect.safe_redirect(conn, "https://good.example/login")

SafeRedirect.safe_redirect(socket, "https://good.example/login")
```

## Validation Rules

- Relative URIs are always considered allowed.
- Paths must not contain dot segments (`.` or `..`).
- Protocol-relative URIs (starting with `//`) are not allowed.
- Given absolute URIs are compared against the configured allowed URIs by
  matching the scheme, host, and port.
- Any path under an allowed base URI is considered valid.
- Paths, query strings, and fragments are ignored when checking the base URI.
- Absolute redirect URIs are only valid if the scheme is `https` or `http`.
