defmodule SafeRedirect do
  @moduledoc """
  Validates and resolves redirect URLs to prevent Open Redirect
  vulnerabilities.

  - `valid_url?/2` returns whether a URL is allowed.
  - `resolve_url/3` returns the URL if it is allowed, or a default value if it
    is not.
  - `redirect/4` resolves the URL and performs the redirect.

  ## Allowed redirect URIs

  All functions take an `:allowed_redirect_uris` option. The value is a list of
  strings or `URI` structs, a single string or `URI` struct, or a
  `{module, function}` tuple that returns such a list. The function is called
  every time a URL is validated.

      SafeRedirect.valid_url?(url,
        allowed_redirect_uris: ["https://good.example"]
      )

      SafeRedirect.valid_url?(url,
        allowed_redirect_uris: {MyAppWeb.RedirectURIs, :allowed_redirect_uris}
      )

  If the option is omitted, the value is read from the application environment
  at call time, defaulting to an empty list.

      config :safe_redirect,
        allowed_redirect_uris: {MyAppWeb.RedirectURIs, :allowed_redirect_uris}

  ## Validation rules

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

  An invalid `:allowed_redirect_uris` option raises `ArgumentError` in every
  function.

  A URL given as a string is parsed with `URI.new/1`, which rejects a host that
  is not ASCII. A `URI` struct is taken as given. If you build a `URI` struct
  from a string, use `URI.new/1` rather than `URI.parse/1`, which does not
  reject such a host.
  """

  # A browser strips tabs, newlines and carriage returns from a URL before
  # parsing it, which can turn a path into a protocol-relative URL pointing at
  # another host. No control character belongs in a redirect target.
  @control_chars Enum.map(0..0x1F, &<<&1>>) ++ ["\x7F"]

  @typedoc """
  A URL, either as a string or as a `URI` struct.
  """
  @type uri_source :: String.t() | URI.t()

  @typedoc """
  The value of the `:allowed_redirect_uris` option.

  See the module documentation for the accepted shapes.
  """
  @type allowed_redirect_uris ::
          [uri_source()] | uri_source() | {module(), atom()}

  @typedoc """
  Options accepted by all functions.
  """
  @type opts :: [allowed_redirect_uris: allowed_redirect_uris()]

  @doc """
  Takes a URL as a string or `URI` struct and determines whether it points to
  an allowed host.

  Relative paths are allowed without checking the allowed URIs. See the module
  documentation for the validation rules and the `:allowed_redirect_uris`
  option.

  ## Examples

      iex> url = "https://good.example/login"
      iex> valid_url?(url, allowed_redirect_uris: ["https://good.example"])
      true

      iex> url = "/login"
      iex> valid_url?(url, allowed_redirect_uris: ["https://good.example"])
      true

      iex> url = "https://evil.example/login"
      iex> valid_url?(url, allowed_redirect_uris: ["https://good.example"])
      false
  """
  @spec valid_url?(uri_source() | nil, opts()) :: boolean
  def valid_url?(url, opts \\ [])

  def valid_url?(nil, _), do: false

  def valid_url?(url, opts) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{} = uri} -> valid_url?(uri, opts)
      {:error, _} -> false
    end
  end

  def valid_url?(%URI{scheme: nil, host: nil, path: "/" <> _ = path}, _) do
    valid_path?(path)
  end

  # A URL with no scheme that is not a root-relative path: a protocol-relative
  # URL, or a relative path such as "foo/bar".
  def valid_url?(%URI{scheme: nil}, _), do: false

  # A scheme with no host is not a redirect target: mailto:, javascript: and
  # data: parse as a scheme plus a path.
  def valid_url?(%URI{host: host}, _) when host in [nil, ""], do: false

  def valid_url?(%URI{path: path} = uri, opts) do
    valid_path?(path) &&
      opts
      |> get_allowed_redirect_uris()
      |> Enum.any?(&uris_match?(&1, uri))
  end

  defp get_allowed_redirect_uris(opts) do
    default = Application.get_env(:safe_redirect, :allowed_redirect_uris, [])

    opts
    |> Keyword.validate!(allowed_redirect_uris: default)
    |> Keyword.fetch!(:allowed_redirect_uris)
    |> allowed_redirect_uris()
  end

  defp allowed_redirect_uris(uris) when is_list(uris) do
    Enum.map(uris, &validate_allowed_redirect_uri/1)
  end

  defp allowed_redirect_uris(uri) when is_binary(uri) or is_struct(uri, URI) do
    allowed_redirect_uris([uri])
  end

  defp allowed_redirect_uris({module, fun})
       when is_atom(module) and is_atom(fun) do
    ensure_exported!(module, fun)

    case apply(module, fun, []) do
      uris when is_list(uris) ->
        allowed_redirect_uris(uris)

      other ->
        raise ArgumentError, """
        #{inspect(module)}.#{fun}/0 returned an invalid value

        A function referenced with {module, function} tuple given as
        :allowed_redirect_uris must return a list of strings or URI structs.

        Got:

            #{inspect(other)}
        """
    end
  end

  defp allowed_redirect_uris(other) do
    raise ArgumentError, """
    invalid :allowed_redirect_uris option

    Expected a list of strings or URI structs, a single string or URI
    struct, or a {module, function} tuple returning such a list.

    Got:

        #{inspect(other)}
    """
  end

  defp ensure_exported!(module, fun) do
    if Code.ensure_loaded?(module) and function_exported?(module, fun, 0) do
      :ok
    else
      raise ArgumentError, """
      invalid :allowed_redirect_uris option

      The tuple given as :allowed_redirect_uris references a function that
      does not exist.

      Expected this function to exist:

          #{inspect(module)}.#{fun}/0
      """
    end
  end

  defp validate_allowed_redirect_uri(uri) when is_binary(uri) do
    case URI.new(uri) do
      {:ok, parsed} -> validate_comparable_uri!(parsed)
      {:error, _} -> :ok
    end

    uri
  end

  defp validate_allowed_redirect_uri(%URI{} = uri) do
    validate_comparable_uri!(uri)
    uri
  end

  defp validate_allowed_redirect_uri(other) do
    raise ArgumentError, """
    invalid entry in the :allowed_redirect_uris option

    Every entry must be a string or a URI struct.

    Got:

        #{inspect(other)}
    """
  end

  defp validate_comparable_uri!(%URI{scheme: scheme, host: host} = uri)
       when is_nil(scheme) or host in [nil, ""] do
    raise ArgumentError, """
    allowed redirect URI without a scheme or host

    Only the scheme, host, and port of an allowed URI are compared. An
    entry missing either can never match.

    Got:

        #{inspect(URI.to_string(uri))}
    """
  end

  defp validate_comparable_uri!(%URI{} = uri) do
    if ignored_uri_parts?(uri) do
      raise ArgumentError, """
      allowed redirect URI with ignored parts

      Only the scheme, host, and port of an allowed URI are compared. Path,
      query, fragment, and userinfo are ignored. Make sure the allowed URIs
      only define the origin.

      Got:

          #{inspect(URI.to_string(uri))}
      """
    end

    if trailing_dot_host?(uri) do
      raise ArgumentError, """
      allowed redirect URI with a trailing dot in the host

      The host is compared exactly, and a trailing dot is part of it. The
      entry would only match URLs that also end with a dot. Write the host
      without it.

      Got:

          #{inspect(URI.to_string(uri))}
      """
    end

    :ok
  end

  defp ignored_uri_parts?(%URI{} = uri) do
    %URI{path: path, query: query, fragment: fragment, userinfo: userinfo} = uri

    path not in [nil, "/"] or not is_nil(query) or not is_nil(fragment) or
      not is_nil(userinfo)
  end

  defp trailing_dot_host?(%URI{host: host}) do
    String.ends_with?(host, ".")
  end

  defp uris_match?(%URI{} = uri_a, %URI{} = uri_b) do
    authority(uri_a) == authority(uri_b)
  end

  defp uris_match?(url, %URI{} = uri_b) when is_binary(url) do
    case URI.new(url) do
      {:ok, uri_a} -> uris_match?(uri_a, uri_b)
      {:error, _} -> false
    end
  end

  defp authority(%URI{host: host, port: port, scheme: scheme}) do
    {String.downcase(host), port, String.downcase(scheme)}
  end

  defp valid_path?(path) when is_binary(path) do
    decoded = URI.decode(path)

    not control_char?(decoded) and
      not protocol_relative?(path) and
      decoded |> Path.split() |> Enum.all?(&(&1 not in [".", ".."]))
  end

  defp valid_path?(nil), do: true

  defp control_char?(<<b, _::binary>>) when b <= 0x1F or b == 0x7F, do: true
  defp control_char?(<<_, rest::binary>>), do: control_char?(rest)
  defp control_char?(<<>>), do: false

  defp protocol_relative?(path) do
    path
    |> URI.decode()
    |> String.replace(@control_chars, "")
    |> String.replace("\\", "/")
    |> String.starts_with?("//")
  end

  @doc """
  Returns the given URL if it is a valid redirect URL or the default value
  otherwise.

  The URL is returned unchanged, so passing a `URI` struct returns a `URI`
  struct. Any other value, including `nil`, returns the default value. The
  default value is returned as given and is not validated.

  See the module documentation for the validation rules and the
  `:allowed_redirect_uris` option.

  ## Examples

      iex> url = "https://good.example/login"
      iex> resolve_url(url, "/", allowed_redirect_uris: ["https://good.example"])
      "https://good.example/login"

      iex> url = "/login"
      iex> resolve_url(url, "/", allowed_redirect_uris: ["https://good.example"])
      "/login"

      iex> url = "https://evil.example/login"
      iex> resolve_url(url, "/", allowed_redirect_uris: ["https://good.example"])
      "/"
  """
  @spec resolve_url(term(), uri_source() | nil, opts()) :: uri_source() | nil
  def resolve_url(url, default \\ "/", opts \\ [])

  def resolve_url(url, default, opts) when is_binary(url) do
    if valid_url?(url, opts), do: url, else: default
  end

  def resolve_url(%URI{} = url, default, opts) do
    if valid_url?(url, opts), do: url, else: default
  end

  def resolve_url(_, default, _), do: default

  if Code.ensure_loaded?(Plug.Conn) do
    @doc """
    Resolves the given URL and performs an internal or external redirect.

    Resolves `url` against the allowed URIs with `resolve_url/3`, falling back
    to `default`, then redirects to the result.

    Accepts a `Plug.Conn` or, when `Phoenix.LiveView` is available, a
    `Phoenix.LiveView.Socket`, and returns the same type it was given.

    A root-relative path is an internal redirect and an absolute `http` or
    `https` URL an external one. For a LiveView socket these are passed to
    `Phoenix.LiveView.redirect/2` as `to:` and `external:`; for a `Plug.Conn`
    both set the `location` header.

    Given a `Plug.Conn`, the connection is halted.

    Raises `ArgumentError` if the resolved URL is neither a relative path nor
    an `http` or `https` URL, for example if the default value is `nil` or if
    an allowed URI uses a different scheme.

    ## Examples

    Using configuration via application environment:

        redirect(conn, url, "/default")

    Passing allowed URIs directly:

        redirect(
          conn,
          url,
          "/default",
          allowed_redirect_uris: ["https://good.example"]
        )
    """
    @spec redirect(Plug.Conn.t(), term(), uri_source(), opts()) ::
            Plug.Conn.t()
    if Code.ensure_loaded?(Phoenix.LiveView) do
      @spec redirect(
              Phoenix.LiveView.Socket.t(),
              term(),
              uri_source(),
              opts()
            ) ::
              Phoenix.LiveView.Socket.t()
    end

    def redirect(conn_or_socket, url, default \\ "/", opts \\ []) do
      {type, redirect_url} =
        url |> resolve_url(default, opts) |> redirect_target()

      do_redirect(conn_or_socket, type, redirect_url)
    end

    defp redirect_target(%URI{} = uri) do
      uri |> URI.to_string() |> redirect_target()
    end

    defp redirect_target("https://" <> _ = url), do: {:external, url}
    defp redirect_target("http://" <> _ = url), do: {:external, url}

    defp redirect_target("/" <> _ = url) do
      if protocol_relative?(url) do
        raise_unredirectable(url)
      else
        {:to, url}
      end
    end

    defp redirect_target(resolved), do: raise_unredirectable(resolved)

    @spec raise_unredirectable(term()) :: no_return()
    defp raise_unredirectable(resolved) do
      raise ArgumentError, """
      cannot redirect to the resolved URL

      SafeRedirect.redirect/4 can only redirect to a relative path starting
      with a single "/" or to an absolute http or https URL. A
      protocol-relative URL points to another host and is refused.

      Resolved value:

          #{inspect(resolved)}

      The resolved value is the given URL if it is allowed, or the default
      value if it is not.
      """
    end

    defp do_redirect(%Plug.Conn{} = conn, _type, url) do
      body =
        "<html><body>You are being <a href=\"#{Plug.HTML.html_escape(url)}\">redirected</a>.</body></html>"

      conn
      |> Plug.Conn.put_resp_header("location", url)
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(conn.status || 302, body)
      |> Plug.Conn.halt()
    end

    if Code.ensure_loaded?(Phoenix.LiveView) do
      defp do_redirect(%Phoenix.LiveView.Socket{} = socket, type, url) do
        Phoenix.LiveView.redirect(socket, [{type, url}])
      end
    end
  end
end
