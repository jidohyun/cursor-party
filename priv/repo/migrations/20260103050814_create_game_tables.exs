defmodule CursorParty.Repo.Migrations.CreateGameTables do
  use Ecto.Migration

  def change do
    # 1. 유저 정보 테이블
    create table(:profiles, primary_key: false) do
      add :id, :string, primary_key: true # user_id (String)
      add :name, :string
      add :gold, :bigint, default: 0
      add :power, :bigint, default: 1
      add :total_damage, :bigint, default: 0
      add :items, :map # 아이템 목록 (JSON 저장)
      add :skill_cd, :map # 스킬 쿨타임 (JSON 저장)

      timestamps()
    end

    # 2. 게임 상태 테이블 (보스 정보 등)
    create table(:game_state) do
      add :key, :string # "boss" 같은 키로 구분
      add :value, :map  # 나머지 데이터 몽땅 JSON으로 저장

      timestamps()
    end

    # 키 검색 속도 향상을 위해 인덱스 추가
    create unique_index(:game_state, [:key])
  end
end
