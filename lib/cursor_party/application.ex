defmodule CursorParty.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CursorPartyWeb.Telemetry,
      CursorParty.Repo,
      {Phoenix.PubSub, name: CursorParty.PubSub},
      {Finch, name: CursorParty.Finch},
      CursorPartyWeb.Presence,
      CursorParty.GameServer,
      CursorPartyWeb.Endpoint
    ]

    # ==========================================================================
    # [추가] 앱 시작 시 자동으로 DB 마이그레이션(테이블 생성) 실행
    # ==========================================================================
    if System.get_env("RELEASE_NAME") != nil or Mix.env() == :prod do
      IO.puts("Running Migrations...")
      Ecto.Migrator.with_repo(CursorParty.Repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    # ==========================================================================

    opts = [strategy: :one_for_one, name: CursorParty.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CursorPartyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
