defmodule CursorParty.GameServer do
  use GenServer

  @db_filename :cursor_party_db
  # 기본 HP (이제 레벨에 따라 달라지므로 초기값만 의미 있음)
  @base_hp_per_level 2000
  @cooldown_ms 100
  @human_limit_ms 50
  @ban_duration_ms 60_000
  @max_level 30

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def hit(user_id, attacker_name), do: GenServer.cast(__MODULE__, {:hit, user_id, attacker_name})
  def get_state, do: GenServer.call(__MODULE__, :get_state)
  def get_hp, do: GenServer.call(__MODULE__, :get_hp)

  def register_profile(user_id, profile),
    do: GenServer.cast(__MODULE__, {:register_profile, user_id, profile})

  def get_profile(user_id), do: GenServer.call(__MODULE__, {:get_profile, user_id})
  def logout(user_id), do: GenServer.cast(__MODULE__, {:logout, user_id})
  def get_all_profiles, do: GenServer.call(__MODULE__, :get_all_profiles)

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_) do
    {:ok, _table} = :dets.open_file(@db_filename, type: :set)

    # [신규] 레벨 불러오기 (없으면 1)
    boss_level = lookup_dets(:boss_level, 1)

    # HP 불러오기 (없으면 레벨 1 기준 HP)
    default_hp = calculate_max_hp(boss_level)
    hp = lookup_dets(:boss_hp, default_hp)

    winner = lookup_dets(:winner, nil)
    profiles = lookup_dets(:profiles, %{})

    {:ok,
     %{
       hp: hp,
       # 상태에 레벨 추가
       boss_level: boss_level,
       winner: winner,
       last_hits: %{},
       banned_users: %{},
       profiles: profiles
     }}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    public_state = Map.drop(state, [:last_hits, :banned_users, :profiles])
    {:reply, public_state, state}
  end

  # ... (기존 API 유지) ...
  @impl true
  def handle_call(:get_hp, _from, state), do: {:reply, state.hp, state}
  @impl true
  def handle_call({:get_profile, user_id}, _from, state),
    do: {:reply, Map.get(state.profiles, user_id), state}

  @impl true
  def handle_call(:get_all_profiles, _from, state), do: {:reply, state.profiles, state}

  @impl true
  def handle_cast({:register_profile, user_id, input_profile}, state) do
    existing = Map.get(state.profiles, user_id, %{})
    merged_profile = Map.merge(input_profile, %{total_damage: existing[:total_damage] || 0})
    new_profiles = Map.put(state.profiles, user_id, merged_profile)
    :dets.insert(@db_filename, {:profiles, new_profiles})
    {:noreply, %{state | profiles: new_profiles}}
  end

  @impl true
  def handle_cast({:logout, user_id}, state) do
    new_profiles = Map.delete(state.profiles, user_id)
    :dets.insert(@db_filename, {:profiles, new_profiles})
    {:noreply, %{state | profiles: new_profiles}}
  end

  @impl true
  def handle_cast({:hit, user_id, attacker_name}, state) do
    now = System.monotonic_time(:millisecond)
    ban_release_time = Map.get(state.banned_users, user_id, now - 1)

    if now < ban_release_time do
      {:noreply, state}
    else
      last_hit_time = Map.get(state.last_hits, user_id, now - 1000)
      diff = now - last_hit_time

      cond do
        diff < @human_limit_ms ->
          new_release_time = now + @ban_duration_ms
          new_banned_users = Map.put(state.banned_users, user_id, new_release_time)

          Phoenix.PubSub.broadcast(
            CursorParty.PubSub,
            "game:boss",
            {:auto_clicker_detected, attacker_name, user_id}
          )

          {:noreply, %{state | banned_users: new_banned_users}}

        diff <= @cooldown_ms ->
          {:noreply, state}

        true ->
          profile = Map.get(state.profiles, user_id)

          new_profiles =
            if profile do
              new_dmg = (profile[:total_damage] || 0) + 1
              p = Map.put(state.profiles, user_id, Map.put(profile, :total_damage, new_dmg))
              :dets.insert(@db_filename, {:profiles, p})
              p
            else
              state.profiles
            end

          new_hp = state.hp - 1
          :dets.insert(@db_filename, {:boss_hp, new_hp})
          new_last_hits = Map.put(state.last_hits, user_id, now)

          if new_hp <= 0 do
            # [신규] 보스 처치 시 레벨업 로직
            # 최대 30레벨까지 증가. 30레벨에서 잡으면 다시 30레벨 (또는 1로 초기화하고 싶으면 1로 변경)
            next_level =
              if state.boss_level >= @max_level, do: state.boss_level, else: state.boss_level + 1

            # 다음 레벨 HP 계산
            next_hp = calculate_max_hp(next_level)

            :dets.insert(@db_filename, {:boss_hp, next_hp})
            :dets.insert(@db_filename, {:boss_level, next_level})
            :dets.insert(@db_filename, {:winner, attacker_name})

            # [수정] 브로드캐스트에 boss_level 추가
            Phoenix.PubSub.broadcast(
              CursorParty.PubSub,
              "game:boss",
              {:boss_update, next_hp, next_level, attacker_name}
            )

            {:noreply,
             %{
               state
               | hp: next_hp,
                 boss_level: next_level,
                 winner: attacker_name,
                 last_hits: new_last_hits,
                 profiles: new_profiles
             }}
          else
            # HP만 감소
            Phoenix.PubSub.broadcast(
              CursorParty.PubSub,
              "game:boss",
              {:boss_update, new_hp, state.boss_level, state.winner}
            )

            {:noreply, %{state | hp: new_hp, last_hits: new_last_hits, profiles: new_profiles}}
          end
      end
    end
  end

  @impl true
  def terminate(_reason, _state), do: :dets.close(@db_filename)

  defp lookup_dets(key, default) do
    case :dets.lookup(@db_filename, key) do
      [{^key, val}] -> val
      [] -> default
    end
  end

  # [신규] 레벨별 최대 체력 계산 함수
  defp calculate_max_hp(level) do
    # 예: 1레벨=2000, 10레벨=20000, 30레벨=60000
    # 더 어렵게 하고 싶으면 지수승(Math.pow) 등을 사용 가능
    level * @base_hp_per_level
  end
end
