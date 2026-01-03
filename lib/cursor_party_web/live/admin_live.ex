defmodule CursorPartyWeb.AdminLive do
  use CursorPartyWeb, :live_view
  alias CursorParty.GameServer
  alias CursorPartyWeb.Presence

  @topic "cursor:lobby"

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CursorParty.PubSub, @topic)
      :timer.send_interval(1000, self(), :tick)
    end

    {:ok, assign_stats(socket)}
  end

  def handle_info(:tick, socket), do: {:noreply, assign_stats(socket)}
  def handle_info(_, socket), do: {:noreply, socket}

  defp assign_stats(socket) do
    game_stats = GameServer.get_admin_stats()
    online_count = Presence.list(@topic) |> map_size()

    assign(socket,
      online: online_count,
      total_users: game_stats.total_profiles,
      boss_level: game_stats.level,
      boss_hp: game_stats.hp,
      banned: game_stats.banned_count,
      # [추가]
      daily_counts: game_stats.daily_counts
    )
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 text-white p-10 font-sans">
      <h1 class="text-3xl font-bold mb-8 text-yellow-400">📊 Game Admin Dashboard</h1>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
        <div class="bg-gray-800 p-6 rounded-xl border border-blue-500/30 shadow-lg">
          <div class="text-gray-400 text-sm uppercase tracking-wider mb-2">🟢 Online Users</div>
          <div class="text-4xl font-bold text-blue-400">{@online}</div>
        </div>
        <div class="bg-gray-800 p-6 rounded-xl border border-purple-500/30 shadow-lg">
          <div class="text-gray-400 text-sm uppercase tracking-wider mb-2">👥 Total Profiles</div>
          <div class="text-4xl font-bold text-purple-400">{@total_users}</div>
        </div>
        <div class="bg-gray-800 p-6 rounded-xl border border-red-500/30 shadow-lg">
          <div class="text-gray-400 text-sm uppercase tracking-wider mb-2">👹 Boss Status</div>
          <div class="text-4xl font-bold text-red-400">Lv.{@boss_level}</div>
          <div class="text-sm text-gray-300 mt-2">
            HP: {Number.Delimit.number_to_delimited(@boss_hp, precision: 0)}
          </div>
        </div>
        <div class="bg-gray-800 p-6 rounded-xl border border-gray-500/30 shadow-lg">
          <div class="text-gray-400 text-sm uppercase tracking-wider mb-2">🚫 Banned Users</div>
          <div class="text-4xl font-bold text-gray-400">{@banned}</div>
        </div>
      </div>

      <div class="bg-gray-800 rounded-xl border border-white/10 p-6 shadow-lg max-w-2xl">
        <h2 class="text-xl font-bold text-white mb-4 flex items-center gap-2">
          📅 Daily Active Users <span class="text-xs font-normal text-gray-400">(Last 7 Days)</span>
        </h2>

        <div class="overflow-hidden rounded-lg border border-white/10">
          <table class="w-full text-left text-sm text-gray-400">
            <thead class="bg-black/30 text-xs uppercase text-gray-200">
              <tr>
                <th scope="col" class="px-6 py-3">Date</th>
                <th scope="col" class="px-6 py-3">Visitors (Unique)</th>
                <th scope="col" class="px-6 py-3">Graph</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-white/5">
              <%= for {date, count} <- @daily_counts do %>
                <tr class="hover:bg-white/5 transition-colors">
                  <td class="px-6 py-4 font-mono">{date}</td>
                  <td class="px-6 py-4 font-bold text-white">{count}</td>
                  <td class="px-6 py-4 w-1/3">
                    <div class="h-2 bg-gray-700 rounded-full overflow-hidden">
                      <div
                        class="h-full bg-gradient-to-r from-blue-500 to-purple-500"
                        style={"width: #{min(count * 2, 100)}%"}
                      >
                      </div>
                    </div>
                  </td>
                </tr>
              <% end %>
              <%= if @daily_counts == [] do %>
                <tr>
                  <td colspan="3" class="px-6 py-8 text-center text-gray-500 italic">No data yet.</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>

      <div class="mt-10">
        <a href="/" class="text-blue-400 hover:text-blue-300 underline">← Back to Game</a>
      </div>
    </div>
    """
  end
end
