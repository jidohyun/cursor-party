defmodule CursorPartyWeb.Presence do
  use Phoenix.Presence,
    otp_app: :cursor_party,
    pubsub_server: CursorParty.PubSub
end
