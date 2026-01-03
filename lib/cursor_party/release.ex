defmodule CursorParty.Release do
  @moduledoc """
  DB hard reset for Koyeb.

  Run:
    /app/bin/cursor_party eval "CursorParty.Release.reset_db()"
  """

  alias CursorParty.Repo
  alias CursorParty.Schema.{Profile, GameState}
  import Ecto.Query

  # 1) Public entry
  def reset_db do
    Application.load(:cursor_party)

    IO.puts("==> Starting required apps...")
    {:ok, _} = Application.ensure_all_started(:ssl)
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Repo.start_link()

    IO.puts("==> Wiping database data...")
    wipe_all_data()

    IO.puts("==> Seeding initial data...")
    seed_initial_data()

    IO.puts("==> Reset done. Stopping VM.")
    :init.stop()
  end

  # 2) Schemas to clear (add here if you create new ones)
  defp all_schemas do
    [
      Profile,
      GameState
      # Example:
      # CursorParty.Schema.Item,
      # CursorParty.Schema.BossLog
    ]
  end

  defp wipe_all_data do
    # Delete in order; if you add FKs, put child tables first.
    Enum.each(all_schemas(), fn schema ->
      {count, _} = Repo.delete_all(schema)
      IO.puts("  - #{inspect(schema)}: #{count} rows deleted")
    end)
  end

  defp seed_initial_data do
    # Boss state
    Repo.insert!(%GameState{
      key: "boss",
      value: %{"hp" => 2000, "level" => 1, "winner" => nil}
    })

    # Daily stats
    Repo.insert!(%GameState{
      key: "daily_stats",
      value: %{}
    })

    # Chat history
    Repo.insert!(%GameState{
      key: "chat",
      value: %{"history" => []}
    })
  end
end
