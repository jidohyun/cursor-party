defmodule CursorParty.Release do
  @moduledoc """
  Koyeb 콘솔에서 실행할 DB 초기화 모듈
  실행법: /app/bin/cursor_party eval "CursorParty.Release.reset_db()"
  """
  alias CursorParty.Repo
  alias CursorParty.Schema.{Profile, GameState}
  import Ecto.Query

  def reset_db do
    # 1. 앱 설정 로드
    Application.load(:cursor_party)

    # 2. [핵심 수정] DB 연결에 필요한 필수 앱들을 수동으로 시작
    # Koyeb DB는 SSL 연결이 필수이므로 :ssl 앱을 꼭 켜야 합니다.
    IO.puts("🔌 필수 앱 시작 중...")
    {:ok, _} = Application.ensure_all_started(:ssl)
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    # 3. 이제 Repo 시작 (이제 에러가 안 날 겁니다)
    {:ok, _} = Repo.start_link()

    IO.puts("⚠️  [Koyeb] 데이터베이스 초기화를 시작합니다...")

    # 4. 데이터 삭제
    Repo.delete_all(Profile)
    Repo.delete_all(GameState)

    # 5. 초기 데이터 주입
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

    # 작업이 끝났으니 프로세스 종료 (깔끔하게)
    :init.stop()
  end
end
