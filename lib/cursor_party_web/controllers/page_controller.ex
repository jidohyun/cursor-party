defmodule CursorPartyWeb.PageController do
  use CursorPartyWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
