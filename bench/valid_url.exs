# Run with: mix run bench/valid_url.exs

defmodule Bench.RedirectURIs do
  def allowed_redirect_uris, do: ["https://good.example"]
end

one = ["https://good.example"]
five = for i <- 1..5, do: "https://h#{i}.example"
twenty = for i <- 1..20, do: "https://h#{i}.example"
hundred = for i <- 1..100, do: "https://h#{i}.example"
tuple = {Bench.RedirectURIs, :allowed_redirect_uris}

uri = URI.new!("https://good.example/x")

Benchee.run(
  %{
    "valid_url?/2 relative path" => fn ->
      SafeRedirect.valid_url?("/some/path", allowed_redirect_uris: one)
    end,
    "valid_url?/2 absolute, 1 entry" => fn ->
      SafeRedirect.valid_url?("https://good.example/x",
        allowed_redirect_uris: one
      )
    end,
    "valid_url?/2 absolute, 5 entries" => fn ->
      SafeRedirect.valid_url?("https://h5.example/x",
        allowed_redirect_uris: five
      )
    end,
    "valid_url?/2 absolute, 20 entries" => fn ->
      SafeRedirect.valid_url?("https://h20.example/x",
        allowed_redirect_uris: twenty
      )
    end,
    "valid_url?/2 absolute, 100 entries" => fn ->
      SafeRedirect.valid_url?("https://h100.example/x",
        allowed_redirect_uris: hundred
      )
    end,
    "valid_url?/2 {module, function}" => fn ->
      SafeRedirect.valid_url?("https://good.example/x",
        allowed_redirect_uris: tuple
      )
    end,
    "valid_url?/2 URI struct" => fn ->
      SafeRedirect.valid_url?(uri, allowed_redirect_uris: one)
    end,
    "resolve_url/3 allowed" => fn ->
      SafeRedirect.resolve_url("https://good.example/x", "/",
        allowed_redirect_uris: one
      )
    end,
    "resolve_url/3 refused" => fn ->
      SafeRedirect.resolve_url("https://evil.example/x", "/",
        allowed_redirect_uris: one
      )
    end,
    "redirect/4 Plug.Conn" =>
      {fn conn ->
         SafeRedirect.redirect(conn, "https://good.example/x", "/",
           allowed_redirect_uris: one
         )
       end, before_each: fn _ -> Plug.Test.conn(:get, "/") end}
  },
  warmup: 1,
  time: 3
)
