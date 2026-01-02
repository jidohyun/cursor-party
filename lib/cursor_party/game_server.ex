defmodule CursorParty.GameServer do
  use GenServer

  @db_filename :cursor_party_db
  @default_hp 999_999
  # 0.1초 (일반 클릭 제한)
  @cooldown_ms 100
  # 0.05초 (오토클리커 감지 기준)
  @human_limit_ms 50
  # 1분 밴
  @ban_duration_ms 60_000

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def hit(user_id, attacker_name) do
    GenServer.cast(__MODULE__, {:hit, user_id, attacker_name})
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def get_hp do
    GenServer.call(__MODULE__, :get_hp)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_) do
    # DB 파일 열기
    {:ok, _table} = :dets.open_file(@db_filename, type: :set)

    # HP 불러오기
    hp =
      case :dets.lookup(@db_filename, :boss_hp) do
        [{:boss_hp, val}] -> val
        [] -> @default_hp
      end

    # 우승자 불러오기
    winner =
      case :dets.lookup(@db_filename, :winner) do
        [{:winner, val}] -> val
        [] -> nil
      end

    # 초기 상태 (last_hits, banned_users 맵 초기화)
    {:ok, %{hp: hp, winner: winner, last_hits: %{}, banned_users: %{}}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    # 클라이언트에는 밴 목록이나 클릭 기록을 보낼 필요 없음
    public_state = Map.drop(state, [:last_hits, :banned_users])
    {:reply, public_state, state}
  end

  @impl true
  def handle_call(:get_hp, _from, state) do
    {:reply, state.hp, state}
  end

  @impl true
  def handle_cast({:hit, user_id, attacker_name}, state) do
    now = System.monotonic_time(:millisecond)

    # 1. 밴 여부 체크 (기록 없으면 통과되게 now - 1)
    ban_release_time = Map.get(state.banned_users, user_id, now - 1)

    if now < ban_release_time do
      {:noreply, state}
    else
      # [수정] 여기가 범인!
      # 기록이 없으면(nil), '1초(1000ms) 전'에 때린 것으로 침.
      # 이러면 diff가 1000이 되므로, 최소 제한(50ms)을 안전하게 통과함.
      last_hit_time = Map.get(state.last_hits, user_id, now - 1000)

      diff = now - last_hit_time

      cond do
        # (A) 오토클리커 감지
        diff < @human_limit_ms ->
          # 1분 밴 설정
          new_release_time = now + @ban_duration_ms
          new_banned_users = Map.put(state.banned_users, user_id, new_release_time)

          Phoenix.PubSub.broadcast(
            CursorParty.PubSub,
            "game:boss",
            {:auto_clicker_detected, attacker_name, user_id}
          )

          {:noreply, %{state | banned_users: new_banned_users}}

        # (B) 쿨타임 미준수
        diff <= @cooldown_ms ->
          {:noreply, state}

        # (C) 정상 클릭
        true ->
          new_hp = state.hp - 1
          :dets.insert(@db_filename, {:boss_hp, new_hp})
          new_last_hits = Map.put(state.last_hits, user_id, now)

          if new_hp <= 0 do
            next_hp = @default_hp
            :dets.insert(@db_filename, {:boss_hp, next_hp})
            :dets.insert(@db_filename, {:winner, attacker_name})

            Phoenix.PubSub.broadcast(
              CursorParty.PubSub,
              "game:boss",
              {:boss_update, next_hp, attacker_name}
            )

            {:noreply, %{state | hp: next_hp, winner: attacker_name, last_hits: new_last_hits}}
          else
            Phoenix.PubSub.broadcast(
              CursorParty.PubSub,
              "game:boss",
              {:boss_update, new_hp, state.winner}
            )

            {:noreply, %{state | hp: new_hp, last_hits: new_last_hits}}
          end
      end
    end
  end

  @impl true
  def terminate(_reason, _state) do
    :dets.close(@db_filename)
  end
end
