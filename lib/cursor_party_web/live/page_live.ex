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

    cursors = list_present_cursors()

    game_state =
      if connected?(socket), do: GameServer.get_state(), else: %{hp: 999_999, winner: nil}

    {:ok,
     assign(socket,
       cursors: cursors,
       boss_hp: game_state.hp,
       winner: game_state.winner,
       my_id: user_id,
       joined?: false,
       my_name: nil,
       my_country: nil,
       form: to_form(%{"name" => "", "country" => "KR"}),
       # 알림 메시지 상태
       alert_msg: nil,
       # 밴 해제 시간
       banned_until: nil
     )}
  end

  # ============================================================================
  # 2. Handle Events (사용자 액션 처리)
  # ============================================================================

  def handle_event("join", %{"name" => name, "country" => country}, socket) do
    name = String.trim(name)

    if String.length(name) >= 3 and String.length(name) <= 20 do
      my_id = socket.assigns.my_id
      color = "#" <> Base.encode16(:crypto.strong_rand_bytes(3))
      flag = get_flag_emoji(country)

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

  def handle_event("cursor-move", %{"x" => x, "y" => y}, socket) do
    if socket.assigns.my_id do
      Presence.update(self(), @topic, socket.assigns.my_id, fn meta ->
        Map.merge(meta, %{
          x: x,
          y: y,
          online_at: System.system_time(:millisecond)
        })
      end)
    end

    {:noreply, socket}
  end

  def handle_event("hit-boss", _params, socket) do
    # 1. 밴 여부 계산
    is_banned =
      if socket.assigns.banned_until do
        DateTime.diff(socket.assigns.banned_until, DateTime.utc_now()) > 0
      else
        false
      end

    # 2. 상태 로그 출력 (터미널 확인용)
    IO.inspect({:hit_check, socket.assigns.joined?, is_banned}, label: "🔍 [PageLive] 클릭 조건 확인")

    # 3. 조건 검사
    if socket.assigns.joined? and not is_banned do
      IO.puts("🚀 [PageLive] 조건 통과! GameServer로 전송합니다.")
      GameServer.hit(socket.assigns.my_id, socket.assigns.my_name)
    else
      IO.puts("⛔ [PageLive] 전송 실패 (참가안함 또는 밴당함)")
    end

    {:noreply, socket}
  end

  # ============================================================================
  # 3. Handle Info (서버 메시지 처리)
  # ============================================================================

  # (1) 오토클리커 적발 알림
  def handle_info({:auto_clicker_detected, name, banned_id}, socket) do
    # 화면 메시지 설정
    msg = "#{name}님의 손놀림이 인간의 한계를 넘어섰습니다!\n시스템이 잠시 휴식을 권장합니다 😌"
    Process.send_after(self(), :clear_alert, 5000)

    # 밴 당한 사람이 '나'라면? -> 로컬 상태 업데이트
    socket =
      if socket.assigns.my_id == banned_id do
        release_time = DateTime.add(DateTime.utc_now(), 60, :second)
        # 1분 뒤 자동 해제 예약
        Process.send_after(self(), :lift_ban, 60000)
        assign(socket, banned_until: release_time)
      else
        socket
      end

    {:noreply, assign(socket, alert_msg: msg)}
  end

  # (2) 알림창 끄기
  def handle_info(:clear_alert, socket) do
    {:noreply, assign(socket, alert_msg: nil)}
  end

  # (3) 밴 해제 (1분 뒤 실행됨)
  def handle_info(:lift_ban, socket) do
    {:noreply, assign(socket, banned_until: nil)}
  end

  # (4) 다른 유저 움직임
  def handle_info(%{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, cursors: list_present_cursors())}
  end

  # (5) 보스 HP 업데이트
  def handle_info({:boss_update, new_hp, winner}, socket) do
    {:noreply, assign(socket, boss_hp: new_hp, winner: winner)}
  end

  # (6) 연결 종료
  def handle_info({:disconnect, _reason}, socket) do
    {:noreply, socket}
  end

  # ============================================================================
  # 4. Terminate & Helpers
  # ============================================================================
  def terminate(_reason, socket) do
    if socket.assigns[:my_id] do
      Presence.untrack(self(), @topic, socket.assigns.my_id)
    end
  end

  defp list_present_cursors do
    Presence.list(@topic)
    |> Enum.map(fn {_k, v} ->
      v.metas
      |> Enum.max_by(&(&1[:online_at] || 0))
    end)
  end

  defp get_flag_emoji(country_code) do
    country_code
    |> String.to_charlist()
    |> Enum.map(&(&1 + 127_397))
    |> List.to_string()
  rescue
    _ -> "🏳️"
  end
end
