defmodule CursorPartyWeb.PageLive do
  use CursorPartyWeb, :live_view
  alias CursorPartyWeb.Presence
  alias CursorParty.GameServer

  @topic "cursor:lobby"
  @boss_topic "game:boss"

  # ============================================================================
  # 1. Mount (초기화)
  # ============================================================================
  # ============================================================================
  # 1. Mount (초기화)
  # ============================================================================
  def mount(_params, session, socket) do
    user_id = session["user_uuid"] || "guest_#{:rand.uniform(10000)}"

    if connected?(socket) do
      Phoenix.PubSub.subscribe(CursorParty.PubSub, @topic)
      Phoenix.PubSub.subscribe(CursorParty.PubSub, @boss_topic)
      :timer.send_interval(1000, self(), :tick)
      GameServer.track_visit(user_id)
    end

    # DB 로드
    saved_profile = if connected?(socket), do: GameServer.get_profile(user_id), else: nil

    # 내 스탯 초기화
    total_damage = if saved_profile, do: Map.get(saved_profile, :total_damage, 0), else: 0
    gold = if saved_profile, do: Map.get(saved_profile, :gold, 0), else: 0
    power = if saved_profile, do: Map.get(saved_profile, :power, 1), else: 1
    my_auto = if saved_profile, do: Map.get(saved_profile, :auto_damage, 0), else: 0
    my_items = if saved_profile, do: Map.get(saved_profile, :items, %{}), else: %{}
    my_skill_cd = if saved_profile, do: Map.get(saved_profile, :skill_cd, %{}), else: %{}

    # 상점 카탈로그 로드
    shop_catalog = GameServer.get_shop_items()

    # 오토 대미지 재계산
    my_auto_calc = calculate_auto_damage(my_items, shop_catalog)
    final_auto = if my_auto_calc > my_auto, do: my_auto_calc, else: my_auto

    # 게임 상태 로드
    game_state =
      if connected?(socket),
        do: GameServer.get_state(),
        else: %{hp: 2000, boss_level: 1, winner: nil, chat_history: []}

    initial_assigns = %{
      cursors: [],
      leaderboard: [],
      boss_hp: game_state.hp,
      boss_level: Map.get(game_state, :boss_level, 1),
      winner: nil,
      winner_countdown: nil,
      chat_messages: Map.get(game_state, :chat_history, []),
      chat_input: "",
      my_id: user_id,
      joined?: false,
      my_name: nil,
      my_country: nil,
      form: to_form(%{"name" => "", "country" => "KR"}),
      alert_msg: nil,
      banned_until: nil,
      my_damage: total_damage,
      my_gold: gold,
      my_power: power,
      my_auto: final_auto,
      my_items: my_items,
      my_skill_cd: my_skill_cd,
      show_shop: false,
      active_shop_tab: :weapon,
      shop_catalog: shop_catalog,
      mobile_tab: :chat
    }

    socket = assign(socket, initial_assigns)

    # [수정] 자동 로그인 처리 (Map.get 사용으로 안전하게 변경)
    socket =
      if saved_profile do
        # DB에 국가 정보가 없으면 기본값 "KR" 사용
        safe_country = Map.get(saved_profile, :raw_country) || "KR"
        safe_name = Map.get(saved_profile, :name) || "Guest"
        safe_color = Map.get(saved_profile, :color) || generate_color(user_id)

        if connected?(socket) do
          Presence.track(self(), @topic, user_id, %{
            x: 50,
            y: 50,
            id: user_id,
            name: safe_name,
            country: safe_country,
            flag: country_to_flag(safe_country),
            color: safe_color,
            online_at: System.system_time(:millisecond)
          })
        end

        assign(socket,
          joined?: true,
          my_name: safe_name,
          my_country: safe_country
        )
      else
        if connected?(socket) do
          Presence.track(self(), @topic, user_id, %{
            x: 50,
            y: 50,
            id: user_id,
            name: nil,
            country: nil,
            color: generate_color(user_id),
            online_at: System.system_time(:millisecond)
          })
        end

        socket
      end

    leaderboard = if connected?(socket), do: build_leaderboard(), else: []

    {:ok, assign(socket, cursors: list_present_cursors(), leaderboard: leaderboard)}
  end

  # ============================================================================
  # 2. Handle Events
  # ============================================================================

  # 2-1. 게임 입장
  def handle_event("join", %{"name" => name, "country" => country}, socket) do
    name = String.trim(name)

    if String.length(name) >= 3 and String.length(name) <= 20 do
      my_id = socket.assigns.my_id
      color = generate_color(my_id)
      flag = country_to_flag(country)

      profile = %{
        name: name,
        country: flag,
        raw_country: country,
        color: color,
        total_damage: socket.assigns.my_damage,
        gold: socket.assigns.my_gold,
        power: socket.assigns.my_power,
        auto_damage: socket.assigns.my_auto,
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

    {:noreply,
     assign(socket,
       joined?: false,
       my_name: nil,
       my_country: nil,
       my_damage: 0,
       my_gold: 0,
       my_power: 1,
       my_auto: 0,
       my_items: %{}
     )}
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

  # 2-4. 보스 공격
  def handle_event("hit-boss", _params, socket) do
    is_banned =
      if socket.assigns.banned_until,
        do: DateTime.diff(socket.assigns.banned_until, DateTime.utc_now()) > 0,
        else: false

    if socket.assigns.joined? and not is_banned and is_nil(socket.assigns.winner_countdown) do
      case GameServer.hit(socket.assigns.my_id, socket.assigns.my_name) do
        {:ok, damage, is_crit} ->
          socket = update(socket, :my_damage, &(&1 + damage))
          socket = update(socket, :my_gold, &(&1 + damage))
          socket = push_event(socket, "damage-effect", %{damage: damage, is_crit: is_crit})
          {:noreply, socket}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # 2-5. 상점 UI 제어
  def handle_event("toggle-shop", _params, socket) do
    socket = push_event(socket, "play-shop-sound", %{})
    {:noreply, assign(socket, show_shop: !socket.assigns.show_shop)}
  end

  def handle_event("close-shop", _params, socket) do
    {:noreply, assign(socket, show_shop: false)}
  end

  # [신규] 상점 탭 변경
  def handle_event("set-shop-tab", %{"tab" => tab_str}, socket) do
    tab = String.to_existing_atom(tab_str)
    {:noreply, assign(socket, active_shop_tab: tab)}
  end

  # 2-6. 아이템 구매 (안전한 패턴 매칭)
  def handle_event("buy-item", %{"id" => item_id}, socket) do
    if socket.assigns.joined? do
      item_atom = String.to_existing_atom(item_id)

      case GameServer.buy_item(socket.assigns.my_id, item_atom) do
        # 5개 리턴 (최신 서버)
        {:ok, new_gold, new_power, new_items, new_auto} ->
          socket = push_event(socket, "play-buy-sound", %{})

          {:noreply,
           assign(socket,
             my_gold: new_gold,
             my_power: new_power,
             my_items: new_items,
             my_auto: new_auto
           )}

        # 4개 리턴 (구버전 호환용)
        {:ok, new_gold, new_power, new_items} ->
          socket = push_event(socket, "play-buy-sound", %{})
          {:noreply, assign(socket, my_gold: new_gold, my_power: new_power, my_items: new_items)}

        {:error, :not_enough_gold} ->
          {:noreply, put_flash(socket, :error, "Not enough gold!")}

        {:error, :already_learned} ->
          {:noreply, put_flash(socket, :error, "You already learned this skill!")}

        _ ->
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

  def handle_event("device-info", %{"deviceType" => device_type}, socket) do
    if socket.assigns.my_id do
      Presence.update(self(), @topic, socket.assigns.my_id, fn meta ->
        Map.put(meta, :device, device_type)
      end)
    end

    {:noreply, socket}
  end

  # ============================================================================
  # 3. Handle Info
  # ============================================================================

  def handle_info(:tick, socket) do
    all_profiles = GameServer.get_all_profiles()
    my_id = socket.assigns.my_id
    my_profile = Map.get(all_profiles, my_id, %{})

    new_gold = my_profile[:gold] || socket.assigns.my_gold
    new_damage = my_profile[:total_damage] || socket.assigns.my_damage
    new_skill_cd = my_profile[:skill_cd] || %{}

    leaderboard = build_leaderboard_from_data(all_profiles)

    {:noreply,
     assign(socket,
       leaderboard: leaderboard,
       my_gold: new_gold,
       my_damage: new_damage,
       my_skill_cd: new_skill_cd
     )}
  end

  # 3-2. 보스 상태 업데이트
  def handle_info({:boss_update, new_hp, level, winner}, socket) do
    IO.puts(">>> [PageLive] 보스 업데이트 수신! HP: #{new_hp}")
    socket = assign(socket, boss_hp: new_hp, boss_level: level)

    socket =
      if winner do
        if socket.assigns.winner != winner do
          push_event(socket, "play-win-sound", %{})
          Process.send_after(self(), :tick_winner_timer, 1000)
          assign(socket, winner: winner, winner_countdown: 5)
        else
          socket
        end
      else
        assign(socket, winner: nil, winner_countdown: nil)
      end

    {:noreply, socket}
  end

  # 3-3. 카운트다운
  def handle_info(:tick_winner_timer, socket) do
    current = socket.assigns.winner_countdown

    if current && current > 1 do
      Process.send_after(self(), :tick_winner_timer, 1000)
      {:noreply, assign(socket, winner_countdown: current - 1)}
    else
      {:noreply, assign(socket, winner: nil, winner_countdown: nil)}
    end
  end

  def handle_info(:clear_winner, socket), do: {:noreply, assign(socket, winner: nil)}

  # 3-4. 채팅 업데이트
  def handle_info({:chat_update, history}, socket) do
    socket = push_event(socket, "play-chat-sound", %{})
    {:noreply, assign(socket, chat_messages: history)}
  end

  # 3-5. 오토클리커 감지
  def handle_info({:auto_clicker_detected, name, banned_id}, socket) do
    msg = "#{name}님의 손놀림이 인간의 한계를 넘어섰습니다!\n잠시 휴식을 권장합니다 😌"
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

  # 3-6. 커서 위치
  def handle_info(%{event: "presence_diff"}, socket),
    do: {:noreply, assign(socket, cursors: list_present_cursors())}

  # [신규] 스킬 발동 이펙트 리스너 (자동 스킬)
  def handle_info({:skill_used, :thunder, _user_id, _dmg}, socket) do
    # 모든 클라이언트에게 번개 이펙트 실행 요청
    socket = push_event(socket, "global-effect", %{type: "thunder"})
    {:noreply, socket}
  end

  def handle_info({:disconnect, _}, socket), do: {:noreply, socket}

  def terminate(_reason, socket) do
    if socket.assigns[:my_id], do: Presence.untrack(self(), @topic, socket.assigns.my_id)
  end

  def handle_event("set-mobile-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, mobile_tab: String.to_existing_atom(tab))}
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp list_present_cursors do
    Presence.list(@topic)
    |> Enum.map(fn {_, v} -> v.metas |> Enum.max_by(&(&1[:online_at] || 0)) end)
  end

  # [수정] 함수 이름을 country_to_flag로 통일
  defp country_to_flag(country_code) do
    country_code |> String.to_charlist() |> Enum.map(&(&1 + 127_397)) |> List.to_string()
  rescue
    _ -> "🏳️"
  end

  # [신규] 유저 ID 기반 고정 컬러 생성
  defp generate_color(user_id) do
    <<r::8, g::8, b::8, _::binary>> = :crypto.hash(:md5, user_id)
    "##{Base.encode16(<<r, g, b>>)}"
  end

  # [신규] 오토 대미지 계산
  defp calculate_auto_damage(user_items, shop_catalog) do
    Enum.reduce(user_items, 0, fn {item_id, count}, acc ->
      item_def = shop_catalog[item_id]

      if item_def && item_def.type == :auto do
        acc + item_def.value * count
      else
        acc
      end
    end)
  end

  # 데이터 기반 리더보드 생성
  defp build_leaderboard do
    all_profiles = GameServer.get_all_profiles()
    build_leaderboard_from_data(all_profiles)
  end

  defp build_leaderboard_from_data(all_profiles) do
    Presence.list(@topic)
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

  defp get_device_icon(meta) do
    if meta[:device] == "Mobile" do
      "📱"
    else
      "💻"
    end
  end

  defp get_device_text(meta) do
    meta[:device] || "Desktop"
  end

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
