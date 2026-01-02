defmodule CursorParty.GameServer do
  use GenServer

  # ============================================================================
  # Constants and Settings
  # ============================================================================
  @db_filename :cursor_party_db
  @base_hp_per_level 2000
  # Click cooldown (0.1s)
  @cooldown_ms 100
  # Auto-clicker detection limit (0.05s)
  @human_limit_ms 50
  # Ban duration (1 minute)
  @ban_duration_ms 60_000
  # Max boss level
  @max_level 30

  # [Shop Item Definitions] - Data Driven
  # Added 'category' field for tab separation in UI
  @shop_items %{
    # --- Weapons ---
    sword: %{
      id: :sword,
      name: "Iron Sword",
      icon: "🗡️",
      desc: "+1 Click Damage",
      base_cost: 100,
      cost_factor: 1.5,
      type: :power,
      value: 1,
      # New field
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
    # --- Skills ---
    skill_thunder: %{
      id: :skill_thunder,
      name: "Grimoire: Thunderbolt",
      icon: "⚡",
      desc: "Auto-cast massive damage every 30s",
      base_cost: 2000,
      # One-time purchase
      cost_factor: 1.0,
      # Skill type
      type: :skill,
      # Damage calculated dynamically
      value: 0,
      # New field
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

  def register_profile(user_id, profile),
    do: GenServer.cast(__MODULE__, {:register_profile, user_id, profile})

  def get_profile(user_id), do: GenServer.call(__MODULE__, {:get_profile, user_id})
  def logout(user_id), do: GenServer.cast(__MODULE__, {:logout, user_id})
  def get_all_profiles, do: GenServer.call(__MODULE__, :get_all_profiles)

  def send_chat(user_id, name, message),
    do: GenServer.cast(__MODULE__, {:new_chat, user_id, name, message})

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_) do
    {:ok, _table} = :dets.open_file(@db_filename, type: :set)

    boss_level = lookup_dets(:boss_level, 1)
    default_hp = calculate_max_hp(boss_level)
    loaded_hp = lookup_dets(:boss_hp, default_hp)
    hp = if boss_level == 1 and loaded_hp > 2000, do: 2000, else: loaded_hp

    winner = lookup_dets(:winner, nil)
    profiles = lookup_dets(:profiles, %{})
    chat_history = lookup_dets(:chat_history, [])

    # Start auto-attack loop (1 second interval) for skills and future pets
    :timer.send_interval(1000, :tick_auto_attack)

    {:ok,
     %{
       hp: hp,
       boss_level: boss_level,
       winner: winner,
       last_hits: %{},
       banned_users: %{},
       profiles: profiles,
       chat_history: chat_history
     }}
  end

  # --- Handle Calls ---

  @impl true
  def handle_call(:get_state, _from, state) do
    public_state = Map.take(state, [:hp, :boss_level, :winner, :chat_history])
    {:reply, public_state, state}
  end

  @impl true
  def handle_call(:get_hp, _from, state), do: {:reply, state.hp, state}
  @impl true
  def handle_call({:get_profile, user_id}, _from, state),
    do: {:reply, Map.get(state.profiles, user_id), state}

  @impl true
  def handle_call(:get_all_profiles, _from, state), do: {:reply, state.profiles, state}

  # [Shop Purchase Logic]
  @impl true
  def handle_call({:buy_item, user_id, item_id}, _from, state) do
    profile = Map.get(state.profiles, user_id)
    item_def = @shop_items[item_id]

    if profile && item_def do
      current_gold = profile[:gold] || 0
      user_items = profile[:items] || %{}
      current_level = Map.get(user_items, item_id, 0)

      # Check if skill book is already learned (max level 1)
      if item_def.type == :skill and current_level >= 1 do
        {:reply, {:error, :already_learned}, state}
      else
        cost = floor(item_def.base_cost * :math.pow(item_def.cost_factor, current_level))

        if current_gold >= cost do
          new_gold = current_gold - cost
          new_level = current_level + 1
          new_user_items = Map.put(user_items, item_id, new_level)

          # Recalculate stats (Power and Auto Damage)
          new_stats =
            Enum.reduce(@shop_items, %{power: 1, auto: 0}, fn {k, def}, acc ->
              lvl = Map.get(new_user_items, k, 0)

              case def.type do
                :power -> Map.put(acc, :power, acc.power + lvl * def.value)
                :auto -> Map.put(acc, :auto, acc.auto + lvl * def.value)
                _ -> acc
              end
            end)

          updated_profile =
            Map.merge(profile, %{
              gold: new_gold,
              items: new_user_items,
              power: new_stats.power,
              auto_damage: new_stats.auto,
              # Ensure skill cooldown map exists
              skill_cd: profile[:skill_cd] || %{}
            })

          new_profiles = Map.put(state.profiles, user_id, updated_profile)
          :dets.insert(@db_filename, {:profiles, new_profiles})

          # Return 5 values: gold, power, items, auto_damage
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

  # [Hit Logic]
  @impl true
  def handle_call({:hit, user_id, attacker_name}, _from, state) do
    now = System.monotonic_time(:millisecond)
    ban_release_time = Map.get(state.banned_users, user_id, now - 1)

    if now < ban_release_time do
      {:reply, {:error, :banned}, state}
    else
      last_hit_time = Map.get(state.last_hits, user_id, now - 1000)
      diff = now - last_hit_time

      cond do
        # Auto-clicker
        diff < @human_limit_ms ->
          new_release_time = now + @ban_duration_ms
          new_banned_users = Map.put(state.banned_users, user_id, new_release_time)

          Phoenix.PubSub.broadcast(
            CursorParty.PubSub,
            "game:boss",
            {:auto_clicker_detected, attacker_name, user_id}
          )

          {:reply, {:error, :ratelimit}, %{state | banned_users: new_banned_users}}

        # Cooldown
        diff <= @cooldown_ms ->
          {:reply, {:error, :cooldown}, state}

        # Success
        true ->
          profile = Map.get(state.profiles, user_id)
          base_power = if profile, do: profile[:power] || 1, else: 1

          is_crit = :rand.uniform(100) <= 15
          final_damage = if is_crit, do: base_power * 2, else: base_power

          new_profiles =
            if profile do
              new_dmg = (profile[:total_damage] || 0) + final_damage
              new_gold = (profile[:gold] || 0) + final_damage

              updated_profile =
                Map.merge(profile, %{total_damage: new_dmg, gold: new_gold, power: base_power})

              p = Map.put(state.profiles, user_id, updated_profile)
              :dets.insert(@db_filename, {:profiles, p})
              p
            else
              state.profiles
            end

          new_hp = state.hp - final_damage
          :dets.insert(@db_filename, {:boss_hp, new_hp})
          new_last_hits = Map.put(state.last_hits, user_id, now)

          if new_hp <= 0 do
            next_level =
              if state.boss_level >= @max_level, do: state.boss_level, else: state.boss_level + 1

            next_hp = calculate_max_hp(next_level)
            :dets.insert(@db_filename, {:boss_hp, next_hp})
            :dets.insert(@db_filename, {:boss_level, next_level})
            :dets.insert(@db_filename, {:winner, attacker_name})

            Phoenix.PubSub.broadcast(
              CursorParty.PubSub,
              "game:boss",
              {:boss_update, next_hp, next_level, attacker_name}
            )

            {:reply, {:ok, final_damage, is_crit},
             %{
               state
               | hp: next_hp,
                 boss_level: next_level,
                 winner: attacker_name,
                 last_hits: new_last_hits,
                 profiles: new_profiles
             }}
          else
            Phoenix.PubSub.broadcast(
              CursorParty.PubSub,
              "game:boss",
              {:boss_update, new_hp, state.boss_level, nil}
            )

            {:reply, {:ok, final_damage, is_crit},
             %{state | hp: new_hp, last_hits: new_last_hits, profiles: new_profiles}}
          end
      end
    end
  end

  # --- Handle Info (Auto Attack & Skills) ---

  # [Auto Attack Loop] - Handles Pets and Skills (30s cooldown)
  @impl true
  def handle_info(:tick_auto_attack, state) do
    now = System.system_time(:millisecond)

    {total_round_dmg, updated_profiles} =
      Enum.reduce(state.profiles, {0, state.profiles}, fn {uid, profile},
                                                          {dmg_acc, profiles_acc} ->
        # 1. Pet Damage (Placeholder for now, prepared for later)
        auto_dmg = profile[:auto_damage] || 0

        # 2. Skill Trigger Check (Thunderbolt)
        has_thunder = get_in(profile, [:items, :skill_thunder]) == 1
        skill_cds = profile[:skill_cd] || %{}
        ready_at = Map.get(skill_cds, :skill_thunder, 0)

        {skill_dmg, new_skill_cds} =
          if has_thunder and now >= ready_at do
            # Damage calculation: (Power * 20) + 50
            dmg = profile[:power] * 20 + 50
            # 30s cooldown
            next_ready = now + 30_000

            # Broadcast effect
            Phoenix.PubSub.broadcast(
              CursorParty.PubSub,
              "game:boss",
              {:skill_used, :thunder, uid, dmg}
            )

            {dmg, Map.put(skill_cds, :skill_thunder, next_ready)}
          else
            {0, skill_cds}
          end

        current_tick_dmg = auto_dmg + skill_dmg

        if current_tick_dmg > 0 do
          new_gold = (profile[:gold] || 0) + current_tick_dmg
          new_total_dmg = (profile[:total_damage] || 0) + current_tick_dmg

          new_profile =
            Map.merge(profile, %{
              gold: new_gold,
              total_damage: new_total_dmg,
              skill_cd: new_skill_cds
            })

          {dmg_acc + current_tick_dmg, Map.put(profiles_acc, uid, new_profile)}
        else
          {dmg_acc, profiles_acc}
        end
      end)

    if total_round_dmg > 0 do
      :dets.insert(@db_filename, {:profiles, updated_profiles})
      new_hp = state.hp - total_round_dmg
      :dets.insert(@db_filename, {:boss_hp, new_hp})

      final_state =
        if new_hp <= 0 do
          next_level =
            if state.boss_level >= @max_level, do: state.boss_level, else: state.boss_level + 1

          next_hp = calculate_max_hp(next_level)
          :dets.insert(@db_filename, {:boss_hp, next_hp})
          :dets.insert(@db_filename, {:boss_level, next_level})
          :dets.insert(@db_filename, {:winner, "Idle Army"})

          Phoenix.PubSub.broadcast(
            CursorParty.PubSub,
            "game:boss",
            {:boss_update, next_hp, next_level, "Idle Army"}
          )

          %{
            state
            | hp: next_hp,
              boss_level: next_level,
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

  # --- Handle Cast ---

  @impl true
  def handle_cast({:register_profile, user_id, input_profile}, state) do
    existing = Map.get(state.profiles, user_id, %{})

    merged_profile =
      Map.merge(input_profile, %{
        total_damage: existing[:total_damage] || 0,
        gold: existing[:gold] || 0,
        power: existing[:power] || 1,
        auto_damage: existing[:auto_damage] || 0,
        items: existing[:items] || %{},
        # Ensure skill_cd exists
        skill_cd: existing[:skill_cd] || %{}
      })

    new_profiles = Map.put(state.profiles, user_id, merged_profile)
    :dets.insert(@db_filename, {:profiles, new_profiles})
    {:noreply, %{state | profiles: new_profiles}}
  end

  @impl true
  def handle_cast({:logout, user_id}, state) do
    new_profiles = Map.delete(state.profiles, user_id)
    {:noreply, %{state | profiles: new_profiles}}
  end

  @impl true
  def handle_cast({:new_chat, user_id, name, message}, state) do
    msg = %{
      id: System.unique_integer([:positive]),
      user_id: user_id,
      name: name,
      text: String.slice(message, 0, 50),
      timestamp: System.system_time(:millisecond)
    }

    new_history = [msg | state.chat_history] |> Enum.take(50)
    Phoenix.PubSub.broadcast(CursorParty.PubSub, "cursor:lobby", {:chat_update, new_history})
    {:noreply, %{state | chat_history: new_history}}
  end

  @impl true
  def terminate(_reason, _state), do: :dets.close(@db_filename)

  # --- Helpers ---

  defp lookup_dets(key, default) do
    case :dets.lookup(@db_filename, key) do
      [{^key, val}] -> val
      [] -> default
    end
  end

  defp calculate_max_hp(level), do: level * @base_hp_per_level
end
