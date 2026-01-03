Elixir

defmodule CursorParty.GameServer do
  use GenServer
  alias CursorParty.Repo
  alias CursorParty.Schema.{Profile, GameState}
  # [핵심] Core 모듈 사용
  alias CursorParty.GameCore

  # 상수 정의 최소화 (설정값 정도만 남김)
  @cooldown_ms 50
  @human_limit_ms 15
  @ban_duration_ms 60_000

  # ============================================================================
  # Client API (변경 없음)
  # ============================================================================
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def hit(user_id, attacker_name), do: GenServer.call(__MODULE__, {:hit, user_id, attacker_name})
  def buy_item(user_id, item_id), do: GenServer.call(__MODULE__, {:buy_item, user_id, item_id})
  # [변경] Core에서 가져옴
  def get_shop_items, do: GameCore.get_shop_items()
  def get_state, do: GenServer.call(__MODULE__, :get_state)
  def get_hp, do: GenServer.call(__MODULE__, :get_hp)
  def get_profile(user_id), do: GenServer.call(__MODULE__, {:get_profile, user_id})
  def get_all_profiles, do: GenServer.call(__MODULE__, :get_all_profiles)
  def get_admin_stats, do: GenServer.call(__MODULE__, :get_admin_stats)

  def create_transfer_code(user_id),
    do: GenServer.call(__MODULE__, {:create_transfer_code, user_id})

  def redeem_transfer_code(code), do: GenServer.call(__MODULE__, {:redeem_transfer_code, code})

  def register_profile(user_id, profile),
    do: GenServer.cast(__MODULE__, {:register_profile, user_id, profile})

  def logout(user_id), do: GenServer.cast(__MODULE__, {:logout, user_id})

  def send_chat(user_id, name, message),
    do: GenServer.cast(__MODULE__, {:new_chat, user_id, name, message})

  def track_visit(user_id), do: GenServer.cast(__MODULE__, {:track_visit, user_id})

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_) do
    boss_data =
      case Repo.get_by(GameState, key: "boss") do
        nil -> %{"hp" => 2000, "level" => 1, "winner" => nil}
        record -> Map.put(record.value, "winner", nil)
      end

    profiles =
      Repo.all(Profile)
      |> Map.new(fn p ->
        items = string_keys_to_atoms(p.items)
        skill_cd = string_keys_to_atoms(p.skill_cd)

        # [변경] Core를 이용해 스탯 계산
        stats = GameCore.calculate_stats(items)

        {p.id,
         %{
           name: p.name,
           gold: p.gold,
           # 저장된 power를 쓰지만, 나중엔 items 기반으로 재계산하는게 더 안전함
           power: p.power,
           total_damage: p.total_damage,
           items: items,
           skill_cd: skill_cd
         }}
      end)

    # ... (daily_stats, chat_history 로딩 로직은 동일) ...
    daily_stats =
      case Repo.get_by(GameState, key: "daily_stats") do
        nil -> %{}
        record -> Map.new(record.value, fn {k, v} -> {k, MapSet.new(v)} end)
      end

    chat_history =
      case Repo.get_by(GameState, key: "chat") do
        nil -> []
        record -> record.value["history"] || []
      end

    :timer.send_interval(1000, :tick_auto_attack)
    :timer.send_interval(10000, :save_db)

    {:ok,
     %{
       hp: boss_data["hp"] || 2000,
       boss_level: boss_data["level"] || 1,
       winner: boss_data["winner"],
       profiles: profiles,
       chat_history: chat_history,
       daily_stats: daily_stats,
       last_hits: %{},
       banned_users: %{},
       transfer_codes: %{}
     }}
  end

  # --- Handle Info (순서 중요) ---

  @impl true
  def handle_info(:save_db, state) do
    # 비동기 Task로 실행하여 게임 로직(GenServer)이 멈추지 않게 함
    # (Task.start를 쓰면 저장하는 동안에도 클릭을 받을 수 있음)
    Task.start(fn ->
      save_everything(state)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(:save_db, state) do
    Task.start(fn -> save_everything(state) end)
    {:noreply, state}
  end

  @impl true
  def handle_info(:tick_auto_attack, state) do
    now = System.system_time(:millisecond)

    {total_dmg, updated_profiles} =
      Enum.reduce(state.profiles, {0, state.profiles}, fn {uid, p}, {d_acc, p_acc} ->
        auto = p[:auto_damage] || 0
        has_thunder = get_in(p, [:items, :skill_thunder]) == 1
        skill_cds = p[:skill_cd] || %{}
        ready_at = Map.get(skill_cds, :skill_thunder, 0)

        {skill_dmg, new_cds} =
          if has_thunder and now >= ready_at do
            # [참고] 이 공식도 나중에 Core로 뺄 수 있음
            dmg = p[:power] * 20 + 50

            Phoenix.PubSub.broadcast(
              CursorParty.PubSub,
              "game:boss",
              {:skill_used, :thunder, uid, dmg}
            )

            {dmg, Map.put(skill_cds, :skill_thunder, now + 30_000)}
          else
            {0, skill_cds}
          end

        tick_dmg = auto + skill_dmg

        if tick_dmg > 0 do
          new_p =
            Map.merge(p, %{
              gold: (p[:gold] || 0) + tick_dmg,
              total_damage: (p[:total_damage] || 0) + tick_dmg,
              skill_cd: new_cds
            })

          {d_acc + tick_dmg, Map.put(p_acc, uid, new_p)}
        else
          {d_acc, p_acc}
        end
      end)

    if total_dmg > 0 do
      apply_damage_to_boss(state, total_dmg, nil, updated_profiles)
    else
      {:noreply, state}
    end
  end

  # --- Handle Call (순서 중요) ---

  @impl true
  def handle_call({:create_transfer_code, user_id}, _from, state) do
    code = Integer.to_string(:rand.uniform(900_000) + 100_000)
    Process.send_after(self(), {:expire_code, code}, 300_000)
    new_codes = Map.put(state.transfer_codes, code, user_id)
    {:reply, {:ok, code}, %{state | transfer_codes: new_codes}}
  end

  @impl true
  def handle_call({:redeem_transfer_code, code}, _from, state) do
    case Map.get(state.transfer_codes, code) do
      nil ->
        {:reply, {:error, :invalid_code}, state}

      target_uuid ->
        new_codes = Map.delete(state.transfer_codes, code)
        {:reply, {:ok, target_uuid}, %{state | transfer_codes: new_codes}}
    end
  end

  @impl true
  def handle_info(:start_new_round, state) do
    IO.puts("⚔️ [New Round] 새로운 보스 전투 시작!")

    # 1. 승리자(winner) 초기화 -> 이제 hit 가능!
    new_state = %{state | winner: nil}

    # 2. 클라이언트에게 "전투 시작!" 알림 (승리 모달 닫힘)
    Phoenix.PubSub.broadcast(
      CursorParty.PubSub,
      "game:boss",
      {:boss_update, state.hp, state.boss_level, nil}
    )

    # 3. DB에도 winner가 없는 상태로 저장
    Task.start(fn -> save_everything(new_state) end)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:expire_code, code}, state) do
    {:noreply, %{state | transfer_codes: Map.delete(state.transfer_codes, code)}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, Map.take(state, [:hp, :boss_level, :winner, :chat_history]), state}
  end

  @impl true
  def handle_call(:get_hp, _from, state), do: {:reply, state.hp, state}

  @impl true
  def handle_call({:get_profile, user_id}, _from, state),
    do: {:reply, Map.get(state.profiles, user_id), state}

  @impl true
  def handle_call(:get_all_profiles, _from, state), do: {:reply, state.profiles, state}
  @impl true
  def handle_call(:get_admin_stats, _from, state) do
    daily =
      state.daily_stats
      |> Enum.map(fn {d, s} -> {d, MapSet.size(s)} end)
      |> Enum.sort_by(&elem(&1, 0), :desc)
      |> Enum.take(7)

    {:reply,
     %{
       hp: state.hp,
       level: state.boss_level,
       total_profiles: map_size(state.profiles),
       banned_count: map_size(state.banned_users),
       daily_counts: daily
     }, state}
  end

  @impl true
  def handle_call({:buy_item, user_id, item_id}, _from, state) do
    profile = Map.get(state.profiles, user_id)

    if profile do
      case GameCore.try_buy_item(profile[:gold] || 0, profile[:items] || %{}, item_id) do
        {:ok, new_gold, new_items, _new_level} ->
          new_stats = GameCore.calculate_stats(new_items)

          updated_profile =
            Map.merge(profile, %{
              gold: new_gold,
              items: new_items,
              power: new_stats.power
            })

          new_profiles = Map.put(state.profiles, user_id, updated_profile)

          {:reply, {:ok, new_gold, new_stats.power, new_items}, %{state | profiles: new_profiles}}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :profile_not_found}, state}
    end
  end

  @impl true
  def handle_call({:hit, user_id, attacker_name}, _from, state) do
    now = System.system_time(:millisecond)
    ban_release = Map.get(state.banned_users, user_id, 0)

    if state.winner do
      {:reply, {:error, :boss_dead}, state}
    else
      cond do
        now < ban_release ->
          {:reply, {:error, :banned}, state}

        is_cooldown?(state, user_id, now) ->
          {:reply, {:error, :cooldown}, state}

        true ->
          # --- 실제 타격 처리 ---
          profile = Map.get(state.profiles, user_id)

          # 1. 아이템 기반 스탯 계산
          user_items = if profile, do: profile[:items] || %{}, else: %{}
          stats = GameCore.calculate_stats(user_items)

          # 2. 데미지 계산 (stats 맵 전체를 넘김)
          {damage, is_crit} = GameCore.calculate_hit(stats)

          new_profiles =
            if profile do
              upd =
                Map.merge(profile, %{
                  total_damage: (profile[:total_damage] || 0) + damage,
                  gold: (profile[:gold] || 0) + damage
                })

              Map.put(state.profiles, user_id, upd)
            else
              state.profiles
            end

          new_hits = Map.put(state.last_hits, user_id, now)

          # 보스 데미지 적용 및 상태 업데이트 공통 함수 호출
          {:noreply, new_state} = apply_damage_to_boss(state, damage, attacker_name, new_profiles)

          # last_hits 업데이트는 별도로 반영
          final_state = %{new_state | last_hits: new_hits}

          {:reply, {:ok, damage, is_crit}, final_state}
      end
    end
  end

  # --- Handle Cast (순서 중요) ---

  @impl true
  def handle_cast({:register_profile, user_id, profile}, state) do
    # ... (기존과 동일) ...
    existing = Map.get(state.profiles, user_id, %{})

    merged =
      Map.merge(profile, %{
        total_damage: existing[:total_damage] || 0,
        gold: existing[:gold] || 0,
        power: existing[:power] || 1,
        items: existing[:items] || %{},
        skill_cd: existing[:skill_cd] || %{},
        auto_damage: existing[:auto_damage] || 0
      })

    {:noreply, %{state | profiles: Map.put(state.profiles, user_id, merged)}}
  end

  @impl true
  def handle_cast({:logout, user_id}, state),
    do: {:noreply, %{state | profiles: Map.delete(state.profiles, user_id)}}

  @impl true
  def handle_cast({:new_chat, user_id, name, msg}, state) do
    # ... (기존과 동일) ...
    new_msg = %{
      "id" => :rand.uniform(1_000_000),
      "user_id" => user_id,
      "name" => name,
      "text" => msg,
      "timestamp" => System.system_time(:millisecond)
    }

    new_history = [new_msg | state.chat_history] |> Enum.take(50)
    Phoenix.PubSub.broadcast(CursorParty.PubSub, "cursor:lobby", {:chat_update, new_history})
    {:noreply, %{state | chat_history: new_history}}
  end

  @impl true
  def handle_cast({:track_visit, user_id}, state) do
    today = Date.utc_today() |> Date.to_string()
    current_set = Map.get(state.daily_stats, today, MapSet.new())

    {:noreply,
     %{state | daily_stats: Map.put(state.daily_stats, today, MapSet.put(current_set, user_id))}}
  end

  # --- Helpers ---
  defp is_cooldown?(state, user_id, now) do
    last_hit = Map.get(state.last_hits, user_id, 0)
    now - last_hit <= @cooldown_ms
  end

  # [공통 함수] 보스에게 데미지 적용 및 레벨업 처리
  defp apply_damage_to_boss(state, damage, winner_name, updated_profiles) do
    new_hp = state.hp - damage

    if new_hp <= 0 do
      # 1. 다음 레벨 정보 계산
      next_lvl = state.boss_level + 1
      next_hp = GameCore.calculate_boss_hp(next_lvl)
      real_winner = winner_name || "Idle Army"

      # 2. 클라이언트에게 "보스 죽음! 승리자는 누구!" 알림
      Phoenix.PubSub.broadcast(
        CursorParty.PubSub,
        "game:boss",
        {:boss_update, next_hp, next_lvl, real_winner}
      )

      # 3. [핵심 추가] 5초(5000ms) 뒤에 "새 라운드 시작" 메시지를 나 자신에게 보냄
      Process.send_after(self(), :start_new_round, 5000)

      # 4. 상태 업데이트 (winner 설정됨 -> 공격 차단 시작)
      {:noreply,
       %{
         state
         | hp: next_hp,
           boss_level: next_lvl,
           # 승리자가 있으므로 hit 함수가 에러를 뱉음 (정상)
           winner: real_winner,
           profiles: updated_profiles
       }}
    else
      # 보스 생존 시
      Phoenix.PubSub.broadcast(
        CursorParty.PubSub,
        "game:boss",
        {:boss_update, new_hp, state.boss_level, nil}
      )

      {:noreply, %{state | hp: new_hp, profiles: updated_profiles}}
    end
  end

  defp upsert_game_state(key, value) do
    %GameState{}
    |> GameState.changeset(%{key: key, value: value})
    |> Repo.insert(on_conflict: :replace_all, conflict_target: [:key])
  end

  defp save_everything(state) do
    # 1. 보스 상태 저장
    boss_val = %{"hp" => state.hp, "level" => state.boss_level, "winner" => state.winner}
    upsert_game_state("boss", boss_val)

    # 2. 프로필 저장
    # (최적화: 변경된 유저만 저장하면 좋지만, 일단 전체 저장도 10초에 한 번이면 괜찮음)
    # Repo.insert는 건건이 쿼리를 날리므로, 유저가 1000명이 넘어가면 repo.insert_all로 바꿔야 함.
    # 지금 단계에선 Enum.each로 충분합니다.
    Enum.each(state.profiles, fn {uid, p} ->
      attrs = %{
        id: uid,
        name: p.name,
        gold: p[:gold],
        power: p[:power],
        total_damage: p[:total_damage],
        items: p[:items],
        skill_cd: p[:skill_cd]
      }

      %Profile{}
      |> Profile.changeset(attrs)
      |> Repo.insert(on_conflict: :replace_all, conflict_target: :id)
    end)

    # 3. 기타 데이터 저장
    daily_stats_json = Map.new(state.daily_stats, fn {k, v} -> {k, MapSet.to_list(v)} end)
    upsert_game_state("daily_stats", daily_stats_json)
    upsert_game_state("chat", %{"history" => state.chat_history})

    IO.puts("💾 [AutoSave] 데이터베이스 저장 완료")
  end

  defp string_keys_to_atoms(nil), do: %{}

  defp string_keys_to_atoms(map) do
    Map.new(map, fn {k, v} ->
      try do
        {String.to_existing_atom(k), v}
      rescue
        _ -> {String.to_atom(k), v}
      end
    end)
  end

  @impl true
  def terminate(_reason, state) do
    IO.puts("🛑 서버 종료 중... 데이터 긴급 저장!")
    save_everything(state)
    :ok
  end
end
