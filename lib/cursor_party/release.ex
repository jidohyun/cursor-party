defmodule CursorParty.Release do
  alias CursorParty.Repo
  alias CursorParty.Schema.{Profile, GameState}
  import Ecto.Query

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

    IO.puts("==> Resetting GameServer state...")
    reset_gameserver_state()

    IO.puts("==> Reset done. Stopping VM.")
    :init.stop()
  end

  defp all_schemas do
    [
      CursorParty.Schema.Profile,
      CursorParty.Schema.GameState
    ]
  end

  defp wipe_all_data do
    Enum.each(all_schemas(), fn schema ->
      {count, _} = Repo.delete_all(schema)
      IO.puts("  - #{inspect(schema)}: #{count} rows deleted")
    end)
  end

  defp seed_initial_data do
    Repo.insert!(%GameState{
      key: "boss",
      value: %{"hp" => 2000, "level" => 1, "winner" => nil}
    })

    Repo.insert!(%GameState{
      key: "daily_stats",
      value: %{}
    })

    Repo.insert!(%GameState{
      key: "chat",
      value: %{"history" => []}
    })
  end

  defp reset_gameserver_state do
    case Process.whereis(CursorParty.GameServer) do
      nil ->
        IO.puts("  - GameServer not running (skipping).")

      pid ->
        case GenServer.call(pid, :reset_state) do
          :ok ->
            IO.puts("  - GameServer state reset to level 1.")

          other ->
            IO.puts("  - GameServer reset returned: #{inspect(other)}")
        end
    end
  end
end
