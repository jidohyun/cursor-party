defmodule CursorParty.GameServer do
  use GenServer

  def start_link(_),
    do: GenServer.start_link(__MODULE__, %{hp: 999_999, winner: nil}, name: __MODULE__)

  def hit(attacker_name) do
    GenServer.cast(__MODULE__, {:hit, attacker_name})
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def get_hp do
    GenServer.call(__MODULE__, :get_hp)
  end

  def init(state), do: {:ok, state}

  def handle_cast({:hit, attacker_name}, state) do
    if state.hp <= 0 do
      {:noreply, state}
    else
      new_hp = max(0, state.hp - 1)
      winner = if new_hp == 0, do: attacker_name, else: state.winner

      Phoenix.PubSub.broadcast(CursorParty.PubSub, "game:boss", {:boss_update, new_hp, winner})

      {:noreply, %{state | hp: new_hp, winner: winner}}
    end
  end

  def handle_call(:get_state, _from, state), do: {:reply, state, state}
  def handle_call(:get_hp, _from, state), do: {:reply, state.hp, state}
end
