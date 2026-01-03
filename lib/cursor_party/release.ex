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
    {:ok, _} = Repo.start_link()

    IO.puts("⚠️  [Koyeb] 데이터베이스 초기화를 시작합니다...")

    # 1. 데이터 삭제 (순서 중요)
    Repo.delete_all(Profile)
    Repo.delete_all(GameState)

    # 2. 초기 데이터 주입
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

    IO.puts("✅  [Koyeb] DB 초기화 및 시드 데이터 주입 완료!")
  end
end
