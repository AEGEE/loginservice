defmodule LoginserviceWeb.LoginControllerTest do
  use LoginserviceWeb.ConnCase, async: true

  @valid_attrs %{email: "some@email.com", name: "some name", password: "some password", active: true}
  alias Loginservice.Auth
  alias Loginservice.Repo


  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(@valid_attrs)
      |> Auth.create_user()

    user
  end

  test "successful login delivers access and refresh token", %{conn: conn} do
    user_fixture()

    conn = post conn, login_path(conn, :login), username: "some name", password: "some password"
    assert json_response(conn, 200)["refresh_token"]
    assert json_response(conn, 200)["access_token"]
    json_response(conn, 200)
  end

  test "unsuccessful login returns an error", %{conn: conn} do
    user_fixture()

    conn = post conn, login_path(conn, :login), username: "some name", password: "some invalid password"
    assert json_response(conn, 400)
  end

  @tag only_me: true
  test "with aquired token, access is possible", %{conn: conn} do
    user_fixture()

    conn = post conn, login_path(conn, :login), username: "some name", password: "some password"
    assert access = json_response(conn, 200)["access_token"]

    conn = conn
    |> recycle()
    |> put_req_header("x-auth-token", access)

    conn = get conn, login_path(conn, :user_data)
    assert json_response(conn, 200)
  end

  test "refresh token can be used to get new access tokens", %{conn: conn} do
    user_fixture()

    conn = post conn, login_path(conn, :login), username: "some name", password: "some password"
    assert refresh = json_response(conn, 200)["refresh_token"]
    assert json_response(conn, 200)["access_token"]

    conn = conn
    |> recycle()

    conn = post conn, login_path(conn, :renew_token), refresh_token: refresh
    assert access = json_response(conn, 200)["access_token"]

    conn = conn
    |> recycle()
    |> put_req_header("x-auth-token", access)

    conn = get conn, login_path(conn, :user_data)
    assert json_response(conn, 200)
  end

  test "logout invalidates the refresh token", %{conn: conn} do
    user_fixture()

    conn = post conn, login_path(conn, :login), username: "some name", password: "some password"
    assert refresh = json_response(conn, 200)["refresh_token"]
    assert access = json_response(conn, 200)["access_token"]

    conn = conn
    |> recycle()
    |> put_req_header("x-auth-token", access)

    conn = post conn, login_path(conn, :logout)
    assert json_response(conn, 200)

    conn = conn
    |> recycle()

    conn = post conn, login_path(conn, :renew_token), refresh_token: refresh
    assert json_response(conn, 403)
  end

  test "can check for username existence", %{conn: conn} do
    user_fixture()

    conn = get conn, login_path(conn, :check_user_existence), username: "some name"
    assert json_response(conn, 200)["exists"] == true

    conn = recycle(conn)

    conn = get conn, login_path(conn, :check_user_existence), username: "some nonexisting name"
    assert json_response(conn, 200)["exists"] == false
  end

  test "can trigger a password forgotten action", %{conn: conn} do
    user = user_fixture()
    :ets.delete_all_objects(:saved_mail)

    conn = post conn, login_path(conn, :password_reset), email: user.email
    assert json_response(conn, 200)

    password_reset = Repo.get_by(Auth.PasswordReset, user_id: user.id)
    assert password_reset != nil

    assert :ets.lookup(:saved_mail, user.email) != []
  end

  test "password forgotten action sends a mail where user can change his password", %{conn: conn} do
    user = user_fixture()
    :ets.delete_all_objects(:saved_mail)

    conn = post conn, login_path(conn, :password_reset), email: user.email
    assert json_response(conn, 200)

    password_reset = Repo.get_by(Auth.PasswordReset, user_id: user.id)
    assert password_reset != nil

    url = :ets.lookup(:saved_mail, user.email)
    |> assert
    |> Enum.at(0)
    |> parse_url_from_mail()

    assert password_reset_new = Auth.get_password_reset_by_url!(url)
    assert password_reset.id == password_reset_new.id
    assert password_reset.url != url

    conn = recycle(conn)

    conn = post conn, login_path(conn, :confirm_password_reset, url), password: "new password"
    assert json_response(conn, 200)

    conn = post conn, login_path(conn, :login), username: user.name, password: "new password"
    assert json_response(conn, 200)["refresh_token"]
    assert json_response(conn, 200)["access_token"]

  end

  defp parse_url_from_mail({_, _, content, _}) do
    # Parse the url token from a content which looks like this:
    # To reset your password, visit www.alastair.com/registration/confirm_reset_password/vXMkHWvQETck73sjQpccFDgQQuavIoDZ

    Application.get_env(:loginservice, :url_prefix) <> "confirm_reset_password/"
    |> Regex.escape
    |> (&(&1 <> "([^\s]*)")).() # esotheric elixir... I am concatenating that regex string to the string in the pipe
    |> Regex.compile!
    |> Regex.run(content)
    |> Enum.at(1)
  end
end
