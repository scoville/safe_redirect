defmodule SafeRedirectTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  doctest SafeRedirect, import: true

  describe "valid_url?/1" do
    test "accepts relative URL" do
      assert SafeRedirect.valid_url?("/some/path", [])
      assert SafeRedirect.valid_url?(URI.new!("/some/path"), [])
    end

    test "accepts relative home URL" do
      assert SafeRedirect.valid_url?("/", [])
    end

    test "does not accept relative URLs starting with . or .." do
      refute SafeRedirect.valid_url?("./some/path", [])
      refute SafeRedirect.valid_url?("../some/path", [])
    end

    test "does not accept relative URLs containing . or .." do
      refute SafeRedirect.valid_url?("/some/./path", [])
      refute SafeRedirect.valid_url?("/some/../path", [])
    end

    test "does not accept relative URLs containing encoded . or .." do
      refute SafeRedirect.valid_url?("/some/%2e/path", [])
      refute SafeRedirect.valid_url?("/some/%2e%2e/path", [])
      refute SafeRedirect.valid_url?("/some/%2E/path", [])
      refute SafeRedirect.valid_url?("/some/%2E%2E/path", [])
    end

    test "does not accept protocol-relative URLs" do
      refute SafeRedirect.valid_url?("//evil.url", [])
      refute SafeRedirect.valid_url?("//evil.example", [])
      refute SafeRedirect.valid_url?("//evil.example/", [])
      refute SafeRedirect.valid_url?("//evil.example/foo", [])

      refute SafeRedirect.valid_url?("//evil.example/foo",
               allowed_redirect_uris: ["https://good.example"]
             )
    end

    test "accepts known absolute URL via list in options" do
      assert SafeRedirect.valid_url?("http://localhost:4000",
               allowed_redirect_uris: ["http://localhost:4000"]
             )

      assert SafeRedirect.valid_url?("http://localhost:4000",
               allowed_redirect_uris: ["http://localhost:4000"]
             )

      assert SafeRedirect.valid_url?("http://localhost:4000/some/path",
               allowed_redirect_uris: ["http://localhost:4000"]
             )

      assert SafeRedirect.valid_url?("https://good.example",
               allowed_redirect_uris: ["https://good.example"]
             )

      assert SafeRedirect.valid_url?("https://good.example/some/path",
               allowed_redirect_uris: ["https://good.example"]
             )

      # options should override application env

      refute SafeRedirect.valid_url?("https://great.example",
               allowed_redirect_uris: ["https://good.example"]
             )
    end

    test "accepts known absolute URL via m/f tuple in options" do
      assert SafeRedirect.valid_url?("https://good.example",
               allowed_redirect_uris: {__MODULE__, :allowed_redirect_uris}
             )
    end

    test "accepts known absolute URL via application environment" do
      assert SafeRedirect.valid_url?("https://great.example")
    end

    test "can handle any combination of URI and string" do
      url = "https://good.example"

      assert SafeRedirect.valid_url?(url, allowed_redirect_uris: [url])

      assert SafeRedirect.valid_url?(URI.new!(url),
               allowed_redirect_uris: [url]
             )

      assert SafeRedirect.valid_url?(url,
               allowed_redirect_uris: [URI.new!(url)]
             )

      assert SafeRedirect.valid_url?(URI.new!(url),
               allowed_redirect_uris: [URI.new!(url)]
             )
    end

    test "does not accept absolute URLs containing . or .." do
      opts = [allowed_redirect_uris: ["https://good.example"]]

      refute SafeRedirect.valid_url?("https://good.example/some/./path", opts)
      refute SafeRedirect.valid_url?("https://good.example/some/../path", opts)
    end

    test "does not accept absolute URLs containing encoded . or .." do
      opts = [allowed_redirect_uris: ["https://good.example"]]

      refute SafeRedirect.valid_url?("https://good.example/some/%2e/path", opts)

      refute SafeRedirect.valid_url?(
               "https://good.example/some/%2e%2e/path",
               opts
             )
    end

    test "does not accept unknown host" do
      refute SafeRedirect.valid_url?("https://good.example", [])
    end

    test "does not accept host with deceptive subdomains" do
      refute SafeRedirect.valid_url?("https://good.example.evil.corp.example",
               allowed_redirect_uris: ["https://good.example"]
             )
    end

    test "does not accept non-matching scheme" do
      refute SafeRedirect.valid_url?("http://good.example",
               allowed_redirect_uris: ["https://good.example"]
             )
    end

    test "does not accept non-matching port" do
      refute SafeRedirect.valid_url?("http://localhost:4001",
               allowed_redirect_uris: ["http://localhost:4000"]
             )
    end

    test "does not accept invalid URL" do
      refute SafeRedirect.valid_url?("¥")
    end
  end

  describe "resolve_url/1" do
    test "returns URL if it is valid" do
      url = "https://good.example/login"
      opts = [allowed_redirect_uris: ["https://good.example"]]

      assert SafeRedirect.resolve_url(url, "/", opts) == url

      url = URI.new!(url)
      assert SafeRedirect.resolve_url(url, "/", opts) == url
    end

    test "ignores invalid allowed URLs" do
      url = "https://good.example/login"
      opts = [allowed_redirect_uris: ["¥", "https://good.example"]]
      assert SafeRedirect.resolve_url(url, "/", opts) == url
    end

    test "returns default URL if URL is invalid" do
      assert SafeRedirect.resolve_url("https://evil.example", "/hi") == "/hi"
    end

    test "returns default default URL if URl is invalid" do
      assert SafeRedirect.resolve_url("https://evil.example") == "/"
    end

    test "returns default URL if URL is nil" do
      assert SafeRedirect.resolve_url(nil) == "/"
    end
  end

  describe "redirect/3" do
    setup do
      %{
        opts: [allowed_redirect_uris: ["https://good.example"]],
        conn: Phoenix.ConnTest.build_conn()
      }
    end

    test "redirects conn to absolute https URL if it is valid", %{
      conn: conn,
      opts: opts
    } do
      url = "https://good.example"
      conn = SafeRedirect.redirect(conn, url, "/", opts)
      assert redirected_to(conn) == url
      assert conn.halted
    end

    test "redirects socket to absolute https URL if it is valid", %{
      opts: opts
    } do
      url = "https://good.example"
      socket = %Phoenix.LiveView.Socket{}
      SafeRedirect.redirect(socket, url, "/", opts)
      # Unclear how to test the redirect without setting up a real LiveView. At
      # least we know it doesn't raise an error.
    end

    test "redirects to absolute http URL if it is valid", %{conn: conn} do
      url = "http://good.example"
      opts = [allowed_redirect_uris: ["http://good.example"]]
      conn = SafeRedirect.redirect(conn, url, "/", opts)
      assert redirected_to(conn) == url
      assert conn.halted
    end

    test "redirects to relative path", %{conn: conn, opts: opts} do
      url = "/kittens"
      conn = SafeRedirect.redirect(conn, url, "/", opts)
      assert redirected_to(conn) == url
      assert conn.halted
    end

    test "redirects to default URL if URL is invalid", %{
      conn: conn,
      opts: opts
    } do
      url = "https://evil.example"
      conn = SafeRedirect.redirect(conn, url, "/path", opts)
      assert redirected_to(conn) == "/path"
      assert conn.halted
    end

    test "redirects to default URL if URL is nil", %{conn: conn, opts: opts} do
      url = nil
      conn = SafeRedirect.redirect(conn, url, "/", opts)
      assert redirected_to(conn) == "/"
      assert conn.halted
    end

    test "redirects to URL given as URI", %{conn: conn, opts: opts} do
      url = URI.new!("https://good.example/kittens")
      conn = SafeRedirect.redirect(conn, url, "/", opts)
      assert redirected_to(conn) == "https://good.example/kittens"
      assert conn.halted
    end

    test "redirects to relative URL given as URI", %{conn: conn, opts: opts} do
      conn = SafeRedirect.redirect(conn, URI.new!("/kittens"), "/", opts)
      assert redirected_to(conn) == "/kittens"
      assert conn.halted
    end

    test "redirects to default URL given as URI", %{conn: conn, opts: opts} do
      url = "https://evil.example"
      conn = SafeRedirect.redirect(conn, url, URI.new!("/path"), opts)
      assert redirected_to(conn) == "/path"
      assert conn.halted
    end

    test "raises if default URL is nil", %{conn: conn, opts: opts} do
      assert_raise ArgumentError, ~r/Resolved value:\s+nil/, fn ->
        SafeRedirect.redirect(conn, "https://evil.example", nil, opts)
      end
    end

    test "raises if resolved URL has an unsupported scheme", %{conn: conn} do
      opts = [allowed_redirect_uris: ["myapp://good.example"]]

      assert_raise ArgumentError, ~r/myapp:\/\/good.example\/kittens/, fn ->
        SafeRedirect.redirect(
          conn,
          "myapp://good.example/kittens",
          "/",
          opts
        )
      end
    end
  end

  def allowed_redirect_uris, do: ["https://good.example"]
end
