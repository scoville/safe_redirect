defmodule SafeRedirect do
  @moduledoc """
  Documentation for `SafeRedirect`.
  """

  # A browser strips tabs, newlines and carriage returns from a URL before
  # parsing it, which can turn a path into a protocol-relative URL pointing at
  # another host. No control character belongs in a redirect target.
  @control_chars Enum.map(0..0x1F, &<<&1>>) ++ ["\x7F"]

  @doc """
  Takes a URL as a string and determines whether it points to an allowed
  host.

  Relative URLs are always considered allowed.

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
  @spec valid_url?(String.t() | URI.t() | nil, keyword) :: boolean
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

  def valid_url?(%URI{scheme: nil}, _) do
    # weird path
    false
  end

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
    opt =
      Keyword.get(
        opts,
        :allowed_redirect_uris,
        Application.get_env(:safe_redirect, :allowed_redirect_uris, [])
      )

    case opt do
      uris when is_list(uris) ->
        uris

      {module, fun} when is_atom(module) and is_atom(fun) ->
        apply(module, fun, [])
    end
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
    {downcase(host), port, downcase(scheme)}
  end

  defp downcase(nil), do: nil
  defp downcase(string), do: String.downcase(string)

  defp valid_path?(path) when is_binary(path) do
    decoded = URI.decode(path)

    not String.contains?(decoded, @control_chars) and
      not protocol_relative?(path) and
      decoded |> Path.split() |> Enum.all?(&(&1 not in [".", ".."]))
  end

  defp valid_path?(nil), do: true

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
  @spec resolve_url(any, String.t() | URI.t() | nil, keyword) :: any
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
    @spec redirect(Plug.Conn.t(), any, String.t() | URI.t(), keyword) ::
            Plug.Conn.t()
    if Code.ensure_loaded?(Phoenix.LiveView) do
      @spec redirect(
              Phoenix.LiveView.Socket.t(),
              any,
              String.t() | URI.t(),
              keyword
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
