defmodule CursorParty.GameServer do
  use GenServer

  # ============================================================================
  # 상수 및 설정
  # ============================================================================
  @db_filename :cursor_party_db
  @base_hp_per_level 2000
  # 클릭 쿨타임 (0.1초)
  @cooldown_ms 100
  # 오토클리커 감지 기준 (0.05초)
  @human_limit_ms 50
  # 밴 지속 시간 (1분)
  @ban_duration_ms 60_000
  # 보스 최대 레벨
  @max_level 30

  # [상점 아이템 정의] - 데이터 주도 방식
  # 새로운 아이템을 추가하려면 이 맵에 등록하기만 하면 됩니다.
  @shop_items %{
    sword: %{
      id: :sword,
      name: "Iron Sword",
      icon: "🗡️",
      desc: "+1 Click Damage",
      base_cost: 100,
      # 레벨업 시 가격 증가율 (1.5배)
      cost_factor: 1.5,
      type: :power,
      value: 1
    },
    axe: %{
      id: :axe,
      name: "Battle Axe",
      icon: "🪓",
      desc: "+5 Click Damage",
      base_cost: 1000,
      cost_factor: 1.6,
      type: :power,
      value: 5
    },
    legend: %{
      id: :legend,
      name: "Excalibur",
      icon: "🌟",
      desc: "+50 Click Damage",
      base_cost: 10000,
      cost_factor: 2.0,
      type: :power,
      value: 50
    }
  }

  # ============================================================================
  # Client API (외부에서 호출하는 함수들)
  # ============================================================================

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  # [수정] hit는 이제 결과를 리턴받아야 하므로 call 사용 (크리티컬, 대미지 수치 확인용)
  def hit(user_id, attacker_name), do: GenServer.call(__MODULE__, {:hit, user_id, attacker_name})

  # [신규] 상점 아이템 구매
  def buy_item(user_id, item_id), do: GenServer.call(__MODULE__, {:buy_item, user_id, item_id})

  # [신규] 상점 목록 조회
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
  # Server Callbacks (내부 로직)
  # ============================================================================

  @impl true
  def init(_) do
    {:ok, _table} = :dets.open_file(@db_filename, type: :set)

    # 데이터 로드 (없으면 기본값)
    boss_level = lookup_dets(:boss_level, 1)

    default_hp = calculate_max_hp(boss_level)
    loaded_hp = lookup_dets(:boss_hp, default_hp)

    # HP 보정: 레벨 1인데 HP가 너무 높으면(구버전 데이터) 초기화
    hp = if boss_level == 1 and loaded_hp > 2000, do: 2000, else: loaded_hp

    winner = lookup_dets(:winner, nil)
    profiles = lookup_dets(:profiles, %{})
    chat_history = lookup_dets(:chat_history, [])

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

  # [아이템 구매 로직] - 범용 처리
  @impl true
  def handle_call({:buy_item, user_id, item_id}, _from, state) do
    profile = Map.get(state.profiles, user_id)
    item_def = @shop_items[item_id]

    if profile && item_def do
      current_gold = profile[:gold] || 0

      # 현재 아이템 레벨 가져오기
      user_items = profile[:items] || %{}
      current_level = Map.get(user_items, item_id, 0)

      # 가격 계산: 기본가 * (증가율 ^ 현재레벨)
      cost = floor(item_def.base_cost * :math.pow(item_def.cost_factor, current_level))

      if current_gold >= cost do
        new_gold = current_gold - cost

        # 레벨업 및 아이템 목록 갱신
        new_level = current_level + 1
        new_user_items = Map.put(user_items, item_id, new_level)

        # [중요] 전체 파워 재계산 (기본 1 + 모든 아이템 효과 합산)
        new_power =
          1 +
            Enum.reduce(@shop_items, 0, fn {k, def}, acc ->
              lvl = Map.get(new_user_items, k, 0)
              if def.type == :power, do: acc + lvl * def.value, else: acc
            end)

        updated_profile =
          Map.merge(profile, %{
            gold: new_gold,
            items: new_user_items,
            power: new_power
          })

        new_profiles = Map.put(state.profiles, user_id, updated_profile)
        :dets.insert(@db_filename, {:profiles, new_profiles})

        # 성공 시: 남은 골드, 갱신된 파워, 갱신된 아이템 목록 반환
        {:reply, {:ok, new_gold, new_power, new_user_items}, %{state | profiles: new_profiles}}
      else
        {:reply, {:error, :not_enough_gold}, state}
      end
    else
      {:reply, {:error, :invalid_item}, state}
    end
  end

  # [보스 타격 로직]
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
        # 오토클리커 감지
        diff < @human_limit_ms ->
          new_release_time = now + @ban_duration_ms
          new_banned_users = Map.put(state.banned_users, user_id, new_release_time)

          Phoenix.PubSub.broadcast(
            CursorParty.PubSub,
            "game:boss",
            {:auto_clicker_detected, attacker_name, user_id}
          )

          {:reply, {:error, :ratelimit}, %{state | banned_users: new_banned_users}}

        # 단순 쿨타임
        diff <= @cooldown_ms ->
          {:reply, {:error, :cooldown}, state}

        # 공격 성공
        true ->
          profile = Map.get(state.profiles, user_id)
          base_power = if profile, do: profile[:power] || 1, else: 1

          # [크리티컬 로직] 15% 확률, 대미지 2배
          is_crit = :rand.uniform(100) <= 15
          final_damage = if is_crit, do: base_power * 2, else: base_power

          # 프로필 갱신 (누적 딜량, 골드)
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

          # 보스 처치 여부 확인
          if new_hp <= 0 do
            # 레벨업 및 HP 리셋
            next_level =
              if state.boss_level >= @max_level, do: state.boss_level, else: state.boss_level + 1

            next_hp = calculate_max_hp(next_level)

            :dets.insert(@db_filename, {:boss_hp, next_hp})
            :dets.insert(@db_filename, {:boss_level, next_level})
            :dets.insert(@db_filename, {:winner, attacker_name})

            # 우승자 브로드캐스트
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
            # 보스 생존 시: winner 자리에 nil을 보내서 클라이언트 오버레이 방지
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

  @impl true
  def handle_cast({:register_profile, user_id, input_profile}, state) do
    existing = Map.get(state.profiles, user_id, %{})

    # [중요] 기존 유저의 골드, 파워, 아이템 정보를 유지하면서 새 정보(이름, 국기) 업데이트
    merged_profile =
      Map.merge(input_profile, %{
        total_damage: existing[:total_damage] || 0,
        gold: existing[:gold] || 0,
        power: existing[:power] || 1,
        items: existing[:items] || %{}
      })

    new_profiles = Map.put(state.profiles, user_id, merged_profile)
    :dets.insert(@db_filename, {:profiles, new_profiles})
    {:noreply, %{state | profiles: new_profiles}}
  end

  @impl true
  def handle_cast({:logout, user_id}, state) do
    # 메모리에서는 삭제하지만 DB에는 남아있음 (재접속 시 복구 가능)
    new_profiles = Map.delete(state.profiles, user_id)
    # 여기서는 DB에서 삭제하지 않음 (유저 데이터 보존)
    {:noreply, %{state | profiles: new_profiles}}
  end

  @impl true
  def handle_cast({:new_chat, user_id, name, message}, state) do
    msg = %{
      id: System.unique_integer([:positive]),
      user_id: user_id,
      name: name,
      # 50자 제한
      text: String.slice(message, 0, 50),
      timestamp: System.system_time(:millisecond)
    }

    # 최근 50개 대화만 유지
    new_history = [msg | state.chat_history] |> Enum.take(50)

    Phoenix.PubSub.broadcast(CursorParty.PubSub, "cursor:lobby", {:chat_update, new_history})
    # :dets.insert(@db_filename, {:chat_history, new_history}) # 필요 시 영구 저장
    {:noreply, %{state | chat_history: new_history}}
  end

  @impl true
  def terminate(_reason, _state), do: :dets.close(@db_filename)

  # 내부 헬퍼 함수들
  defp lookup_dets(key, default) do
    case :dets.lookup(@db_filename, key) do
      [{^key, val}] -> val
      [] -> default
    end
  end

  defp calculate_max_hp(level), do: level * @base_hp_per_level
end
