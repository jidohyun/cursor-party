defmodule CursorPartyWeb.PageLive do
  use CursorPartyWeb, :live_view
  alias CursorPartyWeb.Presence
  alias CursorParty.GameServer

  @topic "cursor:lobby"
  @boss_topic "game:boss"

  def mount(_params, session, socket) do
    user_id = session["user_uuid"] || "guest_#{:rand.uniform(10000)}"

    if connected?(socket) do
      Phoenix.PubSub.subscribe(CursorParty.PubSub, @topic)
      Phoenix.PubSub.subscribe(CursorParty.PubSub, @boss_topic)
      :timer.send_interval(1000, self(), :tick)
    end

    saved_profile = if connected?(socket), do: GameServer.get_profile(user_id), else: nil

    stats = %{
      total_damage: saved_profile[:total_damage] || 0,
      saved_playtime: saved_profile[:playtime] || 0,
      session_seconds: 0
    }

    initial_assigns = %{
      cursors: [],
      # [신규] 접속자 목록
      leaderboard: [],
      boss_hp: 999_999,
      winner: nil,
      my_id: user_id,
      joined?: false,
      my_name: nil,
      my_country: nil,
      form: to_form(%{"name" => "", "country" => "KR"}),
      alert_msg: nil,
      banned_until: nil,
      my_damage: stats.total_damage,
      my_playtime: stats.saved_playtime,
      session_seconds: 0
    }

    socket = assign(socket, initial_assigns)

    socket =
      if saved_profile do
        if connected?(socket) do
          Presence.track(self(), @topic, user_id, %{
            x: 50,
            y: 50,
            id: user_id,
            name: saved_profile.name,
            country: saved_profile.country,
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

    game_state =
      if connected?(socket), do: GameServer.get_state(), else: %{hp: 999_999, winner: nil}

    # 초기 로딩 시 리더보드 구성
    leaderboard = if connected?(socket), do: build_leaderboard(), else: []

    {:ok,
     assign(socket,
       cursors: list_present_cursors(),
       leaderboard: leaderboard,
       boss_hp: game_state.hp,
       winner: game_state.winner
     )}
  end

  # ... (handle_event "join", "logout", "cursor-move", "hit-boss" 기존 동일 - 복사해서 사용) ...
  def handle_event("join", %{"name" => name, "country" => country}, socket) do
    name = String.trim(name)

    if String.length(name) >= 3 and String.length(name) <= 20 do
      my_id = socket.assigns.my_id
      color = "#" <> Base.encode16(:crypto.strong_rand_bytes(3))
      flag = get_flag_emoji(country)

      profile = %{
        name: name,
        country: flag,
        raw_country: country,
        color: color,
        total_damage: socket.assigns.my_damage,
        playtime: socket.assigns.my_playtime
      }

      GameServer.register_profile(my_id, profile)

      Presence.update(self(), @topic, my_id, fn meta ->
        Map.merge(meta, %{
          name: name,
          country: flag,
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
        color: nil,
        online_at: System.system_time(:millisecond)
      }
    end)

    {:noreply,
     assign(socket,
       joined?: false,
       my_name: nil,
       my_country: nil,
       my_damage: 0,
       my_playtime: 0,
       session_seconds: 0
     )}
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
      {:noreply, update(socket, :my_damage, &(&1 + 1))}
    else
      {:noreply, socket}
    end
  end

  # ... (handle_info tick 수정) ...

  # [수정] 1초마다 실행: 시간 증가 + 리더보드 갱신
  def handle_info(:tick, socket) do
    # 1. 내 플레이타임 증가
    socket =
      if socket.assigns.joined?, do: update(socket, :session_seconds, &(&1 + 1)), else: socket

    # 2. 리더보드 데이터 갱신 (1초마다 최신 통계 가져옴)
    new_leaderboard = build_leaderboard()

    {:noreply, assign(socket, leaderboard: new_leaderboard)}
  end

  # ... (나머지 handle_info, terminate, helpers 기존 동일) ...
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

  def handle_info({:boss_update, new_hp, winner}, socket),
    do: {:noreply, assign(socket, boss_hp: new_hp, winner: winner)}

  def handle_info({:disconnect, _}, socket), do: {:noreply, socket}

  def terminate(_reason, socket) do
    if socket.assigns[:my_id] do
      Presence.untrack(self(), @topic, socket.assigns.my_id)

      if socket.assigns.joined?,
        do: GameServer.update_playtime(socket.assigns.my_id, socket.assigns.session_seconds)
    end
  end

  defp list_present_cursors do
    Presence.list(@topic)
    |> Enum.map(fn {_, v} -> v.metas |> Enum.max_by(&(&1[:online_at] || 0)) end)
  end

  defp get_flag_emoji(country_code) do
    country_code |> String.to_charlist() |> Enum.map(&(&1 + 127_397)) |> List.to_string()
  rescue
    _ -> "🏳️"
  end

  def format_time(seconds) do
    h = div(seconds, 3600)
    m = div(rem(seconds, 3600), 60)
    s = rem(seconds, 60)
    if h > 0, do: "#{h}h #{m}m #{s}s", else: "#{m}m #{s}s"
  end

  # [신규] 리더보드 생성 함수
  defp build_leaderboard do
    # 1. 현재 접속 중인 유저 ID 목록 (Presence)
    present_users = Presence.list(@topic)

    # 2. 서버에 저장된 전체 통계 (GameServer)
    all_profiles = GameServer.get_all_profiles()

    # 3. 접속 중인 유저만 필터링하여 리스트 생성
    present_users
    |> Enum.map(fn {user_id, entry} ->
      # Presence 메타데이터 (이름, 국기 등)
      meta = entry.metas |> Enum.max_by(&(&1[:online_at] || 0))

      # GameServer 통계 (딜량, 시간)
      stats = Map.get(all_profiles, user_id, %{})

      # 정보 합치기
      %{
        id: user_id,
        # 이름 없으면 Guest
        name: meta[:name] || "Guest",
        country: meta[:country] || "🏳️",
        color: meta[:color] || "#888",
        total_damage: stats[:total_damage] || 0,
        playtime: stats[:playtime] || 0,
        # 이름이 있어야 정식 참가자
        joined?: meta[:name] != nil
      }
    end)
    # 4. 정식 참가자만 + 딜량 높은 순 정렬
    |> Enum.filter(& &1.joined?)
    |> Enum.sort_by(& &1.total_damage, :desc)
  end
end
