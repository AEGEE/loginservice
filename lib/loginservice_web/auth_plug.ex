defmodule Loginservice.Plugs.Auth do
  import Plug.Conn

  def init(default), do: default

  def call(conn, _default) do
    with token <- get_req_header(conn, "x-auth-token"),
      token <- Enum.at(token, 0),
      {:ok, user, claims} <- Loginservice.Auth.check_access_token(token)
    do
      conn 
      |> assign(:user, user)
      |> assign(:refresh_token_id, claims["refresh"])
      |> assign(:access_token, token)
    else
      {:error, _msg} -> 
        conn
        |> put_status(:forbidden)
        |> put_resp_content_type("application/json")
        |> send_resp(403, Poison.encode!(%{success: false, error: "Invalid access token"}))
        |> halt
    end
  end
end
