defmodule CursorPartyWeb.PageLive do
  use CursorPartyWeb, :live_view
  alias CursorPartyWeb.Presence
  alias CursorParty.GameServer

  @topic "cursor:lobby"
  @boss_topic "game:boss"

  # ============================================================================
  # 1. Mount (초기화)
  # ============================================================================
  def mount(_params, session, socket) do
    user_id = session["user_uuid"] || "guest_#{:rand.uniform(10000)}"

    if connected?(socket) do
      Phoenix.PubSub.subscribe(CursorParty.PubSub, @topic)
      Phoenix.PubSub.subscribe(CursorParty.PubSub, @boss_topic)
      # 1초마다 리더보드 갱신
      :timer.send_interval(1000, self(), :tick)
    end

    # DB에서 유저 정보 로드 (없으면 기본값)
    saved_profile = if connected?(socket), do: GameServer.get_profile(user_id), else: nil

    # 내 스탯 초기화
    total_damage = saved_profile[:total_damage] || 0
    gold = saved_profile[:gold] || 0
    power = saved_profile[:power] || 1
    my_items = saved_profile[:items] || %{}

    # 상점 카탈로그 로드 (GameServer에서 정의된 아이템 목록)
    shop_catalog = GameServer.get_shop_items()

    # 게임 상태 로드 (HP, Level, Winner, Chat)
    game_state =
      if connected?(socket),
        do: GameServer.get_state(),
        else: %{hp: 2000, boss_level: 1, winner: nil, chat_history: []}

    initial_assigns = %{
      cursors: [],
      leaderboard: [],

      # 보스 정보
      boss_hp: game_state.hp,
      boss_level: Map.get(game_state, :boss_level, 1),

      # 우승자 및 카운트다운
      # [중요] 새로고침 시 멈춘 화면 방지를 위해 winner는 nil로 시작
      winner: nil,
      winner_countdown: nil,

      # 채팅
      chat_messages: Map.get(game_state, :chat_history, []),
      chat_input: "",

      # 내 정보
      my_id: user_id,
      joined?: false,
      my_name: nil,
      my_country: nil,
      form: to_form(%{"name" => "", "country" => "KR"}),

      # 알림 및 제재
      alert_msg: nil,
      banned_until: nil,

      # 내 스탯 (실시간 반영용)
      my_damage: total_damage,
      my_gold: gold,
      my_power: power,
      my_items: my_items,

      # 상점 UI 상태
      # 상점 모달 표시 여부
      show_shop: false,
      # 상점 아이템 목록
      shop_catalog: shop_catalog
    }

    socket = assign(socket, initial_assigns)

    # 저장된 프로필이 있다면 자동 로그인 & Presence 트래킹
    socket =
      if saved_profile do
        if connected?(socket) do
          Presence.track(self(), @topic, user_id, %{
            x: 50,
            y: 50,
            id: user_id,
            name: saved_profile.name,
            country: saved_profile.raw_country,
            flag: saved_profile.country,
            color: saved_profile.color,
            online_at: System.system_time(:millisecond)
          })
        end

        assign(socket,
          joined?: true,
          my_name: saved_profile.name,
          my_country: saved_profile.raw_country
        )
      else
        # 미가입 상태라도 커서는 보이게 (이름 없이)
        if connected?(socket) do
          Presence.track(self(), @topic, user_id, %{
            x: 50,
            y: 50,
            id: user_id,
            name: nil,
            country: nil,
            color: nil,
            online_at: System.system_time(:millisecond)
          })
        end

        socket
      end

    leaderboard = if connected?(socket), do: build_leaderboard(), else: []

    {:ok,
     assign(socket,
       cursors: list_present_cursors(),
       leaderboard: leaderboard
     )}
  end

  # ============================================================================
  # 2. Handle Events (사용자 입력 처리)
  # ============================================================================

  # 2-1. 게임 입장 (Join)
  def handle_event("join", %{"name" => name, "country" => country}, socket) do
    name = String.trim(name)

    if String.length(name) >= 3 and String.length(name) <= 20 do
      my_id = socket.assigns.my_id
      color = "#" <> Base.encode16(:crypto.strong_rand_bytes(3))
      flag = get_flag_emoji(country)

      # 프로필 생성 (기존 스탯 유지)
      profile = %{
        name: name,
        country: flag,
        raw_country: country,
        color: color,
        total_damage: socket.assigns.my_damage,
        gold: socket.assigns.my_gold,
        power: socket.assigns.my_power,
        items: socket.assigns.my_items
      }

      GameServer.register_profile(my_id, profile)

      Presence.update(self(), @topic, my_id, fn meta ->
        Map.merge(meta, %{
          name: name,
          country: country,
          flag: flag,
          color: color,
          online_at: System.system_time(:millisecond)
        })
      end)

      {:noreply, assign(socket, joined?: true, my_name: name, my_country: country)}
    else
      {:noreply, put_flash(socket, :error, "Name must be between 3 and 20 characters.")}
    end
  end

  # 2-2. 로그아웃
  def handle_event("logout", _params, socket) do
    user_id = socket.assigns.my_id
    GameServer.logout(user_id)

    Presence.update(self(), @topic, user_id, fn meta ->
      %{
        x: meta.x,
        y: meta.y,
        id: user_id,
        name: nil,
        country: nil,
        flag: nil,
        color: nil,
        online_at: System.system_time(:millisecond)
      }
    end)

    # 로컬 스탯 초기화
    {:noreply,
     assign(socket,
       joined?: false,
       my_name: nil,
       my_country: nil,
       my_damage: 0,
       my_gold: 0,
       my_power: 1,
       my_items: %{}
     )}
  end

  def handle_event("keydown", %{"key" => key}, socket) do
    # 나중에 여기에 "if key == "1", do: ..." 같은 로직을 추가할 수 있습니다.
    # 지금은 그냥 무시합니다.
    {:noreply, socket}
  end

  # 2-3. 커서 이동
  def handle_event("cursor-move", %{"x" => x, "y" => y}, socket) do
    if socket.assigns.my_id do
      Presence.update(self(), @topic, socket.assigns.my_id, fn meta ->
        Map.merge(meta, %{x: x, y: y, online_at: System.system_time(:millisecond)})
      end)
    end

    {:noreply, socket}
  end

  # 2-4. 보스 공격 (Hit) - 크리티컬 및 시각 효과 포함
  def handle_event("hit-boss", _params, socket) do
    is_banned =
      if socket.assigns.banned_until,
        do: DateTime.diff(socket.assigns.banned_until, DateTime.utc_now()) > 0,
        else: false

    # 카운트다운 중이거나 밴 상태면 공격 불가
    if socket.assigns.joined? and not is_banned and is_nil(socket.assigns.winner_countdown) do
      # 서버에 공격 요청 (동기 호출로 결과 받음)
      case GameServer.hit(socket.assigns.my_id, socket.assigns.my_name) do
        {:ok, damage, is_crit} ->
          # 내 화면 스탯 즉시 갱신
          socket = update(socket, :my_damage, &(&1 + damage))
          socket = update(socket, :my_gold, &(&1 + damage))

          # JS로 대미지 정보 전송 -> 시각 효과(숫자 표시, 흔들림, 사운드) 실행
          socket = push_event(socket, "damage-effect", %{damage: damage, is_crit: is_crit})

          {:noreply, socket}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # 2-5. 상점 UI 제어 (열기/닫기)
  def handle_event("toggle-shop", _params, socket) do
    socket = push_event(socket, "play-shop-sound", %{})
    {:noreply, assign(socket, show_shop: !socket.assigns.show_shop)}
  end

  def handle_event("close-shop", _params, socket) do
    {:noreply, assign(socket, show_shop: false)}
  end

  # 2-6. 아이템 구매 (확장형 상점 로직)
  def handle_event("buy-item", %{"id" => item_id}, socket) do
    if socket.assigns.joined? do
      item_atom = String.to_existing_atom(item_id)

      # 결과값 패턴 매칭을 강화하여 오류 방지
      case GameServer.buy_item(socket.assigns.my_id, item_atom) do
        # 1. 최신 버전 (자동 사냥 포함, 5개 리턴)
        {:ok, new_gold, new_power, new_items, new_auto} ->
          socket = push_event(socket, "play-buy-sound", %{})

          {:noreply,
           assign(socket,
             my_gold: new_gold,
             my_power: new_power,
             my_items: new_items,
             my_auto: new_auto
           )}

        # 2. 구 버전 호환 (자동 사냥 미포함, 4개 리턴) -> 이걸로 매칭될 가능성 높음
        {:ok, new_gold, new_power, new_items} ->
          socket = push_event(socket, "play-buy-sound", %{})
          # my_auto는 기존 값 유지
          {:noreply, assign(socket, my_gold: new_gold, my_power: new_power, my_items: new_items)}

        {:error, :not_enough_gold} ->
          {:noreply, put_flash(socket, :error, "Not enough gold!")}

        # 3. 디버깅용: 알 수 없는 응답이 오면 로그 출력
        unexpected ->
          IO.inspect(unexpected, label: "Buy Item Error")
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # 2-7. 채팅
  def handle_event("validate-chat", %{"msg" => msg}, socket),
    do: {:noreply, assign(socket, chat_input: msg)}

  def handle_event("send-chat", %{"msg" => msg}, socket) do
    msg = String.trim(msg)

    if socket.assigns.joined? and msg != "" do
      GameServer.send_chat(socket.assigns.my_id, socket.assigns.my_name, msg)
      {:noreply, assign(socket, chat_input: "")}
    else
      {:noreply, socket}
    end
  end

  # ============================================================================
  # 3. Handle Info (서버 메시지 처리)
  # ============================================================================

  # 3-1. 주기적 틱 (리더보드 갱신)
  def handle_info(:tick, socket), do: {:noreply, assign(socket, leaderboard: build_leaderboard())}

  # 3-2. 보스 상태 업데이트 (카운트다운 로직 포함)
  def handle_info({:boss_update, new_hp, level, winner}, socket) do
    socket = assign(socket, boss_hp: new_hp, boss_level: level)

    socket =
      if winner do
        # 우승자가 생겼고, 아직 내 화면에서 처리가 안 됐다면 (중복 실행 방지)
        if socket.assigns.winner != winner do
          # 승리 사운드
          push_event(socket, "play-win-sound", %{})

          # 1초 뒤부터 카운트다운 타이머 시작
          Process.send_after(self(), :tick_winner_timer, 1000)

          assign(socket, winner: winner, winner_countdown: 5)
        else
          socket
        end
      else
        # 우승자가 없으면 (보스 부활 상태) 초기화
        assign(socket, winner: nil, winner_countdown: nil)
      end

    {:noreply, socket}
  end

  # 3-3. 카운트다운 타이머 (1초마다 감소)
  def handle_info(:tick_winner_timer, socket) do
    current = socket.assigns.winner_countdown

    if current && current > 1 do
      Process.send_after(self(), :tick_winner_timer, 1000)
      {:noreply, assign(socket, winner_countdown: current - 1)}
    else
      # 0초가 되면 화면 치우기
      {:noreply, assign(socket, winner: nil, winner_countdown: nil)}
    end
  end

  # 3-4. 안전장치: 혹시 모를 오버레이 제거
  def handle_info(:clear_winner, socket), do: {:noreply, assign(socket, winner: nil)}

  # 3-5. 채팅 업데이트
  def handle_info({:chat_update, history}, socket) do
    socket = push_event(socket, "play-chat-sound", %{})
    {:noreply, assign(socket, chat_messages: history)}
  end

  # 3-6. 오토클리커 감지
  def handle_info({:auto_clicker_detected, name, banned_id}, socket) do
    msg = "#{name}님의 손놀림이 인간의 한계를 넘어섰습니다!\n시스템이 잠시 휴식을 권장합니다 😌"
    Process.send_after(self(), :clear_alert, 5000)

    socket =
      if socket.assigns.my_id == banned_id do
        release_time = DateTime.add(DateTime.utc_now(), 60, :second)
        Process.send_after(self(), :lift_ban, 60000)
        assign(socket, banned_until: release_time)
      else
        socket
      end

    {:noreply, assign(socket, alert_msg: msg)}
  end

  def handle_info(:clear_alert, socket), do: {:noreply, assign(socket, alert_msg: nil)}
  def handle_info(:lift_ban, socket), do: {:noreply, assign(socket, banned_until: nil)}

  # 3-7. 커서 위치 업데이트
  def handle_info(%{event: "presence_diff"}, socket),
    do: {:noreply, assign(socket, cursors: list_present_cursors())}

  def handle_info({:disconnect, _}, socket), do: {:noreply, socket}

  def terminate(_reason, socket) do
    if socket.assigns[:my_id], do: Presence.untrack(self(), @topic, socket.assigns.my_id)
  end

  # ============================================================================
  # Helpers (보조 함수들)
  # ============================================================================

  defp list_present_cursors do
    Presence.list(@topic)
    |> Enum.map(fn {_, v} -> v.metas |> Enum.max_by(&(&1[:online_at] || 0)) end)
  end

  defp get_flag_emoji(country_code) do
    country_code |> String.to_charlist() |> Enum.map(&(&1 + 127_397)) |> List.to_string()
  rescue
    _ -> "🏳️"
  end

  defp build_leaderboard do
    present_users = Presence.list(@topic)
    all_profiles = GameServer.get_all_profiles()

    present_users
    |> Enum.map(fn {user_id, entry} ->
      meta = entry.metas |> Enum.max_by(&(&1[:online_at] || 0))
      db_stats = Map.get(all_profiles, user_id, %{})

      %{
        id: user_id,
        name: meta[:name] || "Guest",
        country: meta[:flag] || meta[:country] || "🏳️",
        color: meta[:color] || "#888",
        total_damage: db_stats[:total_damage] || 0,
        joined?: meta[:name] != nil
      }
    end)
    |> Enum.filter(& &1.joined?)
    |> Enum.sort_by(& &1.total_damage, :desc)
  end

  # 레벨별 보스 스타일 정의
  def get_boss_style(level) do
    cond do
      level >= 30 ->
        %{
          color: "from-gray-900 via-purple-900 to-black",
          border: "border-purple-500",
          emoji: "👑",
          name: "GOD KING"
        }

      level >= 25 ->
        %{
          color: "from-red-900 via-black to-red-900",
          border: "border-red-600",
          emoji: "👿",
          name: "DEMON LORD"
        }

      level >= 20 ->
        %{
          color: "from-yellow-600 via-yellow-800 to-yellow-600",
          border: "border-yellow-400",
          emoji: "🐉",
          name: "GOLD DRAGON"
        }

      level >= 15 ->
        %{
          color: "from-purple-600 to-indigo-800",
          border: "border-purple-400",
          emoji: "👻",
          name: "ELDER GHOST"
        }

      level >= 10 ->
        %{
          color: "from-blue-600 to-cyan-800",
          border: "border-cyan-400",
          emoji: "🐺",
          name: "DIRE WOLF"
        }

      level >= 5 ->
        %{
          color: "from-red-600 to-red-800",
          border: "border-red-400/50",
          emoji: "👹",
          name: "ORC WARRIOR"
        }

      true ->
        %{
          color: "from-green-600 to-emerald-800",
          border: "border-green-400",
          emoji: "🦠",
          name: "SLIME BOSS"
        }
    end
  end
end
