defmodule CursorParty.Repo do
  use Ecto.Repo,
    otp_app: :cursor_party,
    adapter: Ecto.Adapters.Postgres
end
