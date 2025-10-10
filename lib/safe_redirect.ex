defmodule SafeRedirect do
  @moduledoc """
  Documentation for `SafeRedirect`.
  """

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
  @spec valid_url?(String.t() | URI.t(), keyword) :: boolean
  def valid_url?(url, opts \\ [])

  def valid_url?(url, opts) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{} = uri} -> valid_url?(uri, opts)
      {:error, _} -> false
    end
  end

  def valid_url?(%URI{scheme: nil, path: "/" <> _ = path}, _) do
    valid_path?(path)
  end

  def valid_url?(%URI{scheme: nil}, _) do
    # weird path
    false
  end

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

  defp uris_match?(
         %URI{host: host, port: port, scheme: scheme},
         %URI{host: host, port: port, scheme: scheme}
       ) do
    true
  end

  defp uris_match?(%URI{}, %URI{}) do
    false
  end

  defp uris_match?(url, %URI{} = uri_b) when is_binary(url) do
    case URI.new(url) do
      {:ok, uri_a} -> uris_match?(uri_a, uri_b)
      {:error, _} -> false
    end
  end

  defp valid_path?(path) when is_binary(path) do
    # ensure there are not dot segments
    expanded_path =
      path
      |> URI.decode()
      |> Path.expand("/")

    expanded_path == path
  end

  defp valid_path?(nil), do: true

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
      case resolve_url(url, default, opts) do
        "https://" <> _ = url -> do_redirect(conn_or_socket, external: url)
        "http://" <> _ = url -> do_redirect(conn_or_socket, external: url)
        "/" <> _ = url -> do_redirect(conn_or_socket, to: url)
      end
    end

    defp do_redirect(%Plug.Conn{} = conn, opts) do
      conn
      |> Phoenix.Controller.redirect(opts)
      |> Plug.Conn.halt()
    end

    if Code.ensure_loaded?(Phoenix.LiveView) do
      defp do_redirect(%Phoenix.LiveView.Socket{} = socket, opts) do
        Phoenix.LiveView.redirect(socket, opts)
      end
    end
  end
end
