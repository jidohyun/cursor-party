defmodule CursorPartyWeb.PageLive do
  use CursorPartyWeb, :live_view
  alias CursorPartyWeb.Presence
  alias CursorParty.GameServer

  @topic "cursor:lobby"
  @boss_topic "game:boss"

  # ============================================================================
  # 1. Mount
  # ============================================================================
  def mount(_params, session, socket) do
    user_id = session["user_uuid"] || "guest_#{:rand.uniform(10000)}"

    if connected?(socket) do
      Phoenix.PubSub.subscribe(CursorParty.PubSub, @topic)
      Phoenix.PubSub.subscribe(CursorParty.PubSub, @boss_topic)
      # 1초마다 리더보드 갱신 (딜량 순위용)
      :timer.send_interval(1000, self(), :tick)
    end

    # 내 정보 가져오기 (시간 정보는 제거됨)
    saved_profile = if connected?(socket), do: GameServer.get_profile(user_id), else: nil
    total_damage = saved_profile[:total_damage] || 0

    # 서버 상태 가져오기 (HP, Level, Winner)
    game_state =
      if connected?(socket),
        do: GameServer.get_state(),
        else: %{hp: 2000, boss_level: 1, winner: nil}

    initial_assigns = %{
      cursors: [],
      leaderboard: [],
      boss_hp: game_state.hp,
      boss_level: Map.get(game_state, :boss_level, 1),
      chat_messages: Map.get(game_state, :chat_history, []),
      chat_input: "",
      winner: game_state.winner,
      my_id: user_id,
      joined?: false,
      my_name: nil,
      my_country: nil,
      form: to_form(%{"name" => "", "country" => "KR"}),
      alert_msg: nil,
      banned_until: nil,
      my_damage: total_damage
    }

    socket = assign(socket, initial_assigns)

    # 저장된 프로필이 있다면 자동 로그인 처리
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
  # 2. Handle Events
  # ============================================================================
  def handle_event("validate-chat", %{"msg" => msg}, socket) do
    {:noreply, assign(socket, chat_input: msg)}
  end

  def handle_event("send-chat", %{"msg" => msg}, socket) do
    msg = String.trim(msg)

    if socket.assigns.joined? and msg != "" do
      GameServer.send_chat(socket.assigns.my_id, socket.assigns.my_name, msg)
      # 입력창 비우기
      {:noreply, assign(socket, chat_input: "")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("join", %{"name" => name, "country" => country}, socket) do
    name = String.trim(name)

    if String.length(name) >= 3 and String.length(name) <= 20 do
      my_id = socket.assigns.my_id
      color = "#" <> Base.encode16(:crypto.strong_rand_bytes(3))
      flag = get_flag_emoji(country)

      # 프로필 생성 (딜량 유지)
      profile = %{
        name: name,
        country: flag,
        raw_country: country,
        color: color,
        total_damage: socket.assigns.my_damage
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

    {:noreply, assign(socket, joined?: false, my_name: nil, my_country: nil, my_damage: 0)}
  end

  def handle_event("cursor-move", %{"x" => x, "y" => y}, socket) do
    if socket.assigns.my_id do
      Presence.update(self(), @topic, socket.assigns.my_id, fn meta ->
        Map.merge(meta, %{x: x, y: y, online_at: System.system_time(:millisecond)})
      end)
    end

    {:noreply, socket}
  end

  def handle_event("hit-boss", _params, socket) do
    is_banned =
      if socket.assigns.banned_until,
        do: DateTime.diff(socket.assigns.banned_until, DateTime.utc_now()) > 0,
        else: false

    if socket.assigns.joined? and not is_banned do
      GameServer.hit(socket.assigns.my_id, socket.assigns.my_name)
      # 내 화면 딜량 즉시 업데이트
      {:noreply, update(socket, :my_damage, &(&1 + 1))}
    else
      {:noreply, socket}
    end
  end

  # ============================================================================
  # 3. Handle Info
  # ============================================================================
  def handle_info({:chat_update, history}, socket) do
    # history는 최신순([new, old...])으로 오지만, 화면엔 과거->최신([old, new...])으로 뿌려야 하므로 뒤집음
    {:noreply, assign(socket, chat_messages: history)}
  end

  def handle_info(:tick, socket) do
    {:noreply, assign(socket, leaderboard: build_leaderboard())}
  end

  # [수정] 보스 업데이트 (HP, Level, Winner 수신 + 승리 사운드 트리거)
  def handle_info({:boss_update, new_hp, level, winner}, socket) do
    socket = assign(socket, boss_hp: new_hp, boss_level: level, winner: winner)

    socket =
      if winner do
        # 1. 보스 HP가 리셋되었는지 확인 (막타 친 순간)
        if new_hp >= level * 2000 do
          push_event(socket, "play-win-sound", %{})
        end

        # 2. [추가] 4초 뒤에 축하 메시지 지우기 예약
        Process.send_after(self(), :clear_winner, 4000)

        socket
      else
        socket
      end

    {:noreply, socket}
  end

  # [신규] 우승자 정보 초기화 (오버레이 닫기)
  def handle_info(:clear_winner, socket) do
    {:noreply, assign(socket, winner: nil)}
  end

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

  def handle_info(%{event: "presence_diff"}, socket),
    do: {:noreply, assign(socket, cursors: list_present_cursors())}

  def handle_info({:disconnect, _}, socket), do: {:noreply, socket}

  def terminate(_reason, socket) do
    if socket.assigns[:my_id] do
      Presence.untrack(self(), @topic, socket.assigns.my_id)
    end
  end

  # ============================================================================
  # Helpers
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

  # 리더보드: 딜량(total_damage) 기준 정렬
  defp build_leaderboard do
    present_users = Presence.list(@topic)
    all_profiles = GameServer.get_all_profiles()

    present_users
    |> Enum.map(fn {user_id, entry} ->
      meta = entry.metas |> Enum.max_by(&(&1[:online_at] || 0))
      db_stats = Map.get(all_profiles, user_id, %{})
      damage = db_stats[:total_damage] || 0

      %{
        id: user_id,
        name: meta[:name] || "Guest",
        country: meta[:flag] || meta[:country] || "🏳️",
        color: meta[:color] || "#888",
        total_damage: damage,
        joined?: meta[:name] != nil
      }
    end)
    |> Enum.filter(& &1.joined?)
    |> Enum.sort_by(& &1.total_damage, :desc)
  end

  # [신규] 레벨별 보스 스타일 정의 함수 (HTML에서 호출됨)
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
