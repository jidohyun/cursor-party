defmodule CursorParty.GameServer do
  use GenServer
  alias CursorParty.Repo
  alias CursorParty.Schema.{Profile, GameState}
  # import Ecto.Query  <-- 사용하지 않으므로 제거 (Warning 해결)

  # ============================================================================
  # 상수
  # ============================================================================
  @base_hp_per_level 2000
  @cooldown_ms 50
  @human_limit_ms 15
  @ban_duration_ms 60_000
  @max_level 30

  @shop_items %{
    sword: %{
      id: :sword,
      name: "Iron Sword",
      icon: "🗡️",
      desc: "+1 Click Damage",
      base_cost: 100,
      cost_factor: 1.5,
      type: :power,
      value: 1,
      category: :weapon
    },
    axe: %{
      id: :axe,
      name: "Battle Axe",
      icon: "🪓",
      desc: "+5 Click Damage",
      base_cost: 1000,
      cost_factor: 1.6,
      type: :power,
      value: 5,
      category: :weapon
    },
    legend: %{
      id: :legend,
      name: "Excalibur",
      icon: "🌟",
      desc: "+50 Click Damage",
      base_cost: 10000,
      cost_factor: 2.0,
      type: :power,
      value: 50,
      category: :weapon
    },
    skill_thunder: %{
      id: :skill_thunder,
      name: "Grimoire: Thunderbolt",
      icon: "⚡",
      desc: "Auto-cast massive damage every 30s",
      base_cost: 2000,
      cost_factor: 1.0,
      type: :skill,
      value: 0,
      category: :skill
    }
  }

  # ============================================================================
  # Client API
  # ============================================================================
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def hit(user_id, attacker_name), do: GenServer.call(__MODULE__, {:hit, user_id, attacker_name})
  def buy_item(user_id, item_id), do: GenServer.call(__MODULE__, {:buy_item, user_id, item_id})
  def get_shop_items, do: @shop_items
  def get_state, do: GenServer.call(__MODULE__, :get_state)
  def get_hp, do: GenServer.call(__MODULE__, :get_hp)
  def get_profile(user_id), do: GenServer.call(__MODULE__, {:get_profile, user_id})
  def get_all_profiles, do: GenServer.call(__MODULE__, :get_all_profiles)
  def get_admin_stats, do: GenServer.call(__MODULE__, :get_admin_stats)

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
        record -> record.value
      end

    profiles =
      Repo.all(Profile)
      |> Map.new(fn p ->
        items = string_keys_to_atoms(p.items)
        skill_cd = string_keys_to_atoms(p.skill_cd)

        {p.id,
         %{
           name: p.name,
           gold: p.gold,
           power: p.power,
           total_damage: p.total_damage,
           items: items,
           skill_cd: skill_cd,
           auto_damage: calculate_auto_damage(items)
         }}
      end)

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
       banned_users: %{}
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
      new_hp = state.hp - total_dmg

      final_state =
        if new_hp <= 0 do
          next_lvl =
            if state.boss_level >= @max_level, do: state.boss_level, else: state.boss_level + 1

          next_hp = next_lvl * @base_hp_per_level

          Phoenix.PubSub.broadcast(
            CursorParty.PubSub,
            "game:boss",
            {:boss_update, next_hp, next_lvl, "Idle Army"}
          )

          %{
            state
            | hp: next_hp,
              boss_level: next_lvl,
              winner: "Idle Army",
              profiles: updated_profiles
          }
        else
          Phoenix.PubSub.broadcast(
            CursorParty.PubSub,
            "game:boss",
            {:boss_update, new_hp, state.boss_level, nil}
          )

          %{state | hp: new_hp, profiles: updated_profiles}
        end

      {:noreply, final_state}
    else
      {:noreply, state}
    end
  end

  # --- Handle Call (순서 중요) ---

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
    item_def = @shop_items[item_id]

    if profile && item_def do
      current_gold = profile[:gold] || 0
      user_items = profile[:items] || %{}
      current_level = Map.get(user_items, item_id, 0)

      if item_def.type == :skill and current_level >= 1 do
        {:reply, {:error, :already_learned}, state}
      else
        cost = floor(item_def.base_cost * :math.pow(item_def.cost_factor, current_level))

        if current_gold >= cost do
          new_gold = current_gold - cost
          new_level = current_level + 1
          new_user_items = Map.put(user_items, item_id, new_level)
          new_stats = calculate_stats(new_user_items)

          updated_profile =
            Map.merge(profile, %{
              gold: new_gold,
              items: new_user_items,
              power: new_stats.power,
              auto_damage: new_stats.auto,
              skill_cd: profile[:skill_cd] || %{}
            })

          new_profiles = Map.put(state.profiles, user_id, updated_profile)

          {:reply, {:ok, new_gold, new_stats.power, new_user_items, new_stats.auto},
           %{state | profiles: new_profiles}}
        else
          {:reply, {:error, :not_enough_gold}, state}
        end
      end
    else
      {:reply, {:error, :invalid_item}, state}
    end
  end

  @impl true
  def handle_call({:hit, user_id, attacker_name}, _from, state) do
    # [수정] monotonic_time -> system_time (재시작해도 시간 오류 안 나게 변경)
    now = System.system_time(:millisecond)

    # 1. 밴 확인
    ban_release = Map.get(state.banned_users, user_id, 0)

    if now < ban_release do
      # 남은 시간 계산 (로그용)
      remaining = ban_release - now
      IO.puts("🚫 [Hit 거절] #{user_id} 밴 됨. 남은 시간: #{remaining}ms")
      {:reply, {:error, :banned}, state}
    else
      # [수정] system_time 기준으로 변경
      last_hit = Map.get(state.last_hits, user_id, 0)
      diff = now - last_hit

      # 2. 오토클리커 감지
      if diff < @human_limit_ms do
        IO.puts("🤖 [Hit 거절] 오토 의심! 간격: #{diff}ms")

        # 1분 밴
        new_bans = Map.put(state.banned_users, user_id, now + @ban_duration_ms)

        Phoenix.PubSub.broadcast(
          CursorParty.PubSub,
          "cursor:lobby",
          {:auto_clicker_detected, attacker_name, user_id}
        )

        {:reply, {:error, :ratelimit}, %{state | banned_users: new_bans}}
      else
        # 3. 쿨타임 확인
        if diff <= @cooldown_ms do
          {:reply, {:error, :cooldown}, state}
        else
          # --- 공격 성공 ---

          profile = Map.get(state.profiles, user_id)
          base_power = if profile, do: profile[:power] || 1, else: 1

          is_crit = :rand.uniform(100) <= 15
          damage = if is_crit, do: base_power * 2, else: base_power

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

          new_hp = state.hp - damage
          new_hits = Map.put(state.last_hits, user_id, now)

          # 2. 보스 처치 로직
          if new_hp <= 0 do
            next_lvl =
              if state.boss_level >= @max_level, do: state.boss_level, else: state.boss_level + 1

            next_hp = next_lvl * @base_hp_per_level

            Phoenix.PubSub.broadcast(
              CursorParty.PubSub,
              "game:boss",
              {:boss_update, next_hp, next_lvl, attacker_name}
            )

            # [선택] 보스 처치는 중요한 이벤트니 이때만 즉시 저장해도 됩니다.
            # 하지만 성능을 위해 이것도 메모리만 바꾸고 나중에 저장해도 됩니다.
            # 여기서는 즉시 저장을 뺍니다. (save_db가 알아서 할 것임)

            {:reply, {:ok, damage, is_crit},
             %{
               state
               | hp: next_hp,
                 boss_level: next_lvl,
                 winner: attacker_name,
                 last_hits: new_hits,
                 profiles: new_profiles
             }}
          else
            Phoenix.PubSub.broadcast(
              CursorParty.PubSub,
              "game:boss",
              {:boss_update, new_hp, state.boss_level, nil}
            )

            {:reply, {:ok, damage, is_crit},
             %{state | hp: new_hp, last_hits: new_hits, profiles: new_profiles}}
          end
        end
      end
    end
  end

  # --- Handle Cast (순서 중요) ---

  @impl true
  def handle_cast({:register_profile, user_id, profile}, state) do
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
  def handle_cast({:logout, user_id}, state) do
    {:noreply, %{state | profiles: Map.delete(state.profiles, user_id)}}
  end

  @impl true
  def handle_cast({:new_chat, user_id, name, msg}, state) do
    new_msg = %{
      id: System.unique_integer([:positive]),
      user_id: user_id,
      name: name,
      text: String.slice(msg, 0, 50),
      timestamp: System.system_time(:millisecond)
    }

    hist = [new_msg | state.chat_history] |> Enum.take(50)
    Phoenix.PubSub.broadcast(CursorParty.PubSub, "cursor:lobby", {:chat_update, hist})
    {:noreply, %{state | chat_history: hist}}
  end

  @impl true
  def handle_cast({:track_visit, user_id}, state) do
    today = Date.utc_today() |> Date.to_string()
    current_set = Map.get(state.daily_stats, today, MapSet.new())

    {:noreply,
     %{state | daily_stats: Map.put(state.daily_stats, today, MapSet.put(current_set, user_id))}}
  end

  # --- Helpers ---

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

  defp calculate_stats(items) do
    Enum.reduce(@shop_items, %{power: 1, auto: 0}, fn {k, def}, acc ->
      lvl = Map.get(items, k, 0)

      case def.type do
        :power -> Map.put(acc, :power, acc.power + lvl * def.value)
        :auto -> Map.put(acc, :auto, acc.auto + lvl * def.value)
        _ -> acc
      end
    end)
  end

  defp calculate_auto_damage(items), do: calculate_stats(items).auto

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
