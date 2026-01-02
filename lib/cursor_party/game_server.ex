defmodule CursorParty.GameServer do
  use GenServer

  @db_filename :cursor_party_db
  @default_hp 999_999
  @cooldown_ms 100
  @human_limit_ms 50
  @ban_duration_ms 60_000

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def hit(user_id, attacker_name), do: GenServer.cast(__MODULE__, {:hit, user_id, attacker_name})
  def get_state, do: GenServer.call(__MODULE__, :get_state)
  def get_hp, do: GenServer.call(__MODULE__, :get_hp)

  def register_profile(user_id, profile),
    do: GenServer.cast(__MODULE__, {:register_profile, user_id, profile})

  def get_profile(user_id), do: GenServer.call(__MODULE__, {:get_profile, user_id})
  def logout(user_id), do: GenServer.cast(__MODULE__, {:logout, user_id})

  def update_playtime(user_id, seconds),
    do: GenServer.cast(__MODULE__, {:update_playtime, user_id, seconds})

  def get_all_profiles do
    GenServer.call(__MODULE__, :get_all_profiles)
  end

  @impl true
  def init(_) do
    {:ok, _table} = :dets.open_file(@db_filename, type: :set)
    hp = lookup_dets(:boss_hp, @default_hp)
    winner = lookup_dets(:winner, nil)
    profiles = lookup_dets(:profiles, %{})
    {:ok, %{hp: hp, winner: winner, last_hits: %{}, banned_users: %{}, profiles: profiles}}
  end

  @impl true
  def handle_call(:get_all_profiles, _from, state) do
    {:reply, state.profiles, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    public_state = Map.drop(state, [:last_hits, :banned_users, :profiles])
    {:reply, public_state, state}
  end

  @impl true
  def handle_call(:get_hp, _from, state), do: {:reply, state.hp, state}
  @impl true
  def handle_call({:get_profile, user_id}, _from, state),
    do: {:reply, Map.get(state.profiles, user_id), state}

  @impl true
  def handle_cast({:register_profile, user_id, input_profile}, state) do
    existing = Map.get(state.profiles, user_id, %{})

    merged_profile =
      Map.merge(input_profile, %{
        total_damage: existing[:total_damage] || 0,
        playtime: existing[:playtime] || 0
      })

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
  def handle_cast({:update_playtime, user_id, seconds}, state) do
    profile = Map.get(state.profiles, user_id)

    if profile do
      new_time = (profile[:playtime] || 0) + seconds
      new_profile = Map.put(profile, :playtime, new_time)
      new_profiles = Map.put(state.profiles, user_id, new_profile)
      :dets.insert(@db_filename, {:profiles, new_profiles})
      {:noreply, %{state | profiles: new_profiles}}
    else
      {:noreply, state}
    end
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
          # 통계 업데이트
          profile = Map.get(state.profiles, user_id)

          new_profiles =
            if profile do
              new_dmg = (profile[:total_damage] || 0) + 1
              updated_profile = Map.put(profile, :total_damage, new_dmg)
              p = Map.put(state.profiles, user_id, updated_profile)
              :dets.insert(@db_filename, {:profiles, p})
              p
            else
              state.profiles
            end

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

            {:noreply,
             %{
               state
               | hp: next_hp,
                 winner: attacker_name,
                 last_hits: new_last_hits,
                 profiles: new_profiles
             }}
          else
            Phoenix.PubSub.broadcast(
              CursorParty.PubSub,
              "game:boss",
              {:boss_update, new_hp, state.winner}
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
end
