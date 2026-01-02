defmodule CursorParty.GeoIP do
  @moduledoc """
  Simple GeoIP lookup for country codes using country.is API.
  No API key required, perfect for demo apps.
  """

  def get_country_code(ip \\ nil) do
    # Localhost check
    if ip in ["127.0.0.1", "::1", nil] do
      # Return a random country for testing/development
      Enum.random(["KR", "US", "JP", "CN", "DE", "FR", "GB"])
    else
      url = "https://api.country.is/#{ip}"

      case Req.get(url, receive_timeout: 1000) do
        {:ok, %{status: 200, body: %{"country" => country}}} ->
          country

        _ ->
          # Fallback to random if API fails
          Enum.random(["KR", "US", "JP", "GB"])
      end
    end
  end
end
