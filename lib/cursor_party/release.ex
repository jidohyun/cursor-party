defmodule CursorParty.Release do
  @moduledoc """
  Koyeb 콘솔에서 실행할 DB 초기화 모듈
  실행법: /app/bin/cursor_party eval "CursorParty.Release.reset_db()"
  """
  alias CursorParty.Repo
  alias CursorParty.Schema.{Profile, GameState}
  import Ecto.Query

  def reset_db do
    Application.load(:cursor_party)

    IO.puts("🔌 필수 앱 시작 중...")
    {:ok, _} = Application.ensure_all_started(:ssl)
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Repo.start_link()

    IO.puts("⚠️  [Koyeb] 데이터베이스 초기화를 시작합니다...")

    # 아래에서 실제 초기화 로직만 정리
    wipe_all_data()
    seed_initial_data()

    IO.puts("✅  [Koyeb] DB 초기화 및 시드 데이터 주입 완료!")

    :init.stop()
  end

  defp all_schemas do
    [
      CursorParty.Schema.Profile,
      CursorParty.Schema.GameState
      # 나중에 스키마 늘어나면 여기에만 추가
      # CursorParty.Schema.SomeLog,
      # CursorParty.Schema.Item, ...
    ]
  end

  defp wipe_all_data do
    # FK 제약이 있으면 역순으로 지우는 게 안전
    IO.puts("🧨 모든 스키마 데이터 삭제 중...")

    Enum.each(all_schemas(), fn schema ->
      {count, _} = Repo.delete_all(schema)
      IO.puts(" - #{inspect(schema)}: #{count} rows deleted")
    end)
  end

  defp seed_initial_data do
    IO.puts("🌱 초기 데이터 삽입 중...")

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
end
