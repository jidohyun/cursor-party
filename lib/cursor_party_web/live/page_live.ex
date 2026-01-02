defmodule CursorPartyWeb.PageLive do
  use CursorPartyWeb, :live_view
  alias CursorPartyWeb.Presence
  alias CursorParty.GameServer

  @topic "cursor:lobby"
  @boss_topic "game:boss"

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CursorParty.PubSub, @topic)
      Phoenix.PubSub.subscribe(CursorParty.PubSub, @boss_topic)
    end

    cursors = list_present_cursors()

    game_state =
      if connected?(socket), do: GameServer.get_state(), else: %{hp: 999_999, winner: nil}

    {:ok,
     assign(socket,
       cursors: cursors,
       boss_hp: game_state.hp,
       winner: game_state.winner,
       my_id: nil,
       joined?: false,
       my_name: nil,
       my_country: nil,
       form: to_form(%{"name" => "", "country" => "KR"})
     )}
  end

  def handle_event("join", %{"name" => name, "country" => country}, socket) do
    name = String.trim(name)

    if String.length(name) >= 3 and String.length(name) <= 20 do
      id = Base.encode16(:crypto.strong_rand_bytes(16))
      color = "#" <> Base.encode16(:crypto.strong_rand_bytes(3))
      flag = get_flag_emoji(country)

      {:ok, _} =
        Presence.track(self(), @topic, id, %{
          x: 50,
          y: 50,
          color: color,
          id: id,
          country: flag,
          name: name
        })

      {:noreply, assign(socket, joined?: true, my_id: id, my_name: name, my_country: country)}
    else
      {:noreply, put_flash(socket, :error, "Name must be between 3 and 20 characters.")}
    end
  end

  def handle_event("cursor-move", %{"x" => x, "y" => y}, socket) do
    if socket.assigns.joined? do
      my_id = socket.assigns.my_id

      Presence.update(self(), @topic, my_id, fn meta ->
        Map.merge(meta, %{x: x, y: y})
      end)
    end

    {:noreply, socket}
  end

  def handle_event("hit-boss", _params, socket) do
    if socket.assigns.joined? do
      GameServer.hit(socket.assigns.my_name)
    end

    {:noreply, socket}
  end

  def handle_info(%{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, cursors: list_present_cursors())}
  end

  def handle_info({:boss_update, new_hp, winner}, socket) do
    {:noreply, assign(socket, boss_hp: new_hp, winner: winner)}
  end

  defp list_present_cursors do
    Presence.list(@topic)
    |> Enum.map(fn {_k, v} -> v.metas |> List.first() end)
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
