defmodule Loginservice.Auth do
  @moduledoc """
  The Auth context.
  """

  import Ecto.Query, warn: false
  alias Loginservice.Repo

  alias Loginservice.Auth.User
  alias Loginservice.Auth.RefreshToken
  alias Loginservice.Auth.PasswordReset

  def list_users do
    Repo.all(User)
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email!(email), do: Repo.get_by!(User, email: email)
  def get_user_by_member_id!(member_id) when is_binary(member_id) do
    {member_id, ""} = Integer.parse(member_id)
    get_user_by_member_id!(member_id)
  end
  def get_user_by_member_id!(member_id) when is_integer(member_id), do: Repo.get_by!(User, member_id: member_id)

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def update_user_member_id(%User{} = user, member_id) when is_binary(member_id) do
    with {member_id, ""} <- Integer.parse(member_id) do
      update_user_member_id(user, member_id)
    end
  end

  def update_user_member_id(%User{} = user, member_id) when is_integer(member_id) do
    user
    |> User.changeset(%{})
    |> Ecto.Changeset.put_change(:member_id, member_id)
    |> Repo.update()
  end

  def update_user_superadmin(%User{} = user, superadmin) when is_boolean(superadmin) do
    user
    |> User.changeset(%{})
    |> Ecto.Changeset.put_change(:superadmin, superadmin)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  def change_user(%User{} = user) do
    User.changeset(user, %{})
  end

  def check_user_existence(username) do
    query = from u in User, where: u.name == ^username
    case Repo.one(query) do
      nil -> false
      _ -> true
    end
  end

  # Invalidates all refresh tokens of the user, completely logging him out
  def logout_user(user) do
    query = from u in RefreshToken, where: u.user_id == ^user.id
    {deletes, _} = Repo.delete_all(query)
    {:ok, deletes}
  end

  # Invalidates a single refresh token
  def logout_token(refresh_token_id) do
    with {:ok, token} <- Loginservice.test_nil(Repo.get(RefreshToken, refresh_token_id)),
      {:ok, token} <- Repo.delete(token),
    do: {:ok, token}
  end

  # Check user credentials and on success generate tokens
  def login_user(username, password, device \\ "Unknown device") do
    with {:ok, user} <- authenticate_user(username, password),
        {:ok, refresh_token, refresh_token_db} <- create_refresh_token(user, device),
        {:ok, access_token, _claims} <- create_access_token(user, refresh_token_db),
    do: {:ok, user, access_token, refresh_token}
  end

  # Generates a new access token based on a valid refresh token
  def renew_token(refresh_token) do
    with {:ok, user, refresh_token_db} <- check_refresh_token(refresh_token),
      {:ok, access, _claims} <- create_access_token(user, refresh_token_db),
    do: {:ok, access}
  end

  # Check a refresh token for validity
  # Checks for validity of the token and whether the token is in db
  # Returns {:ok, user, token_db} or {:error, any}
  def check_refresh_token(refresh_token) do
    with {:ok, user, _claims} <- Loginservice.Auth.Guardian.resource_from_token(refresh_token, typ: "refresh"),
      {:ok, refresh_token_db} <- check_saved_refresh_token(refresh_token),
    do: {:ok, user, refresh_token_db}
  end

  # DB Check
  defp check_saved_refresh_token(refresh_token) do
    case Repo.get_by(RefreshToken, token: refresh_token) do
      token when token != nil -> {:ok, token}
      nil -> {:error, nil}
    end  
  end

  # Check an access token for validity
  # Just requires a check with the Guardian library
  # Returns {:ok, user, claims} or {:error, any}
  def check_access_token(access_token) do
    Loginservice.Auth.Guardian.resource_from_token(access_token, typ: "access")
  end

  # Create a longlived refresh token
  def create_refresh_token(user, device) do
    with {:ok, refresh_token, _claims} <- Loginservice.Auth.Guardian.encode_and_sign(user, %{}, token_type: "refresh", ttl: {Application.get_env(:loginservice, :ttl_refresh), :seconds}),
      {:ok, refresh_token_db} <- save_refresh_token(refresh_token, user, device),
    do: {:ok, refresh_token, refresh_token_db}
  end

  # Save the refresh token to DB
  defp save_refresh_token(refresh_token, user, device) do
    %RefreshToken{}
    |> RefreshToken.changeset(%{user_id: user.id, token: to_string(refresh_token), device: device})
    |> Repo.insert()
  end

  # Access tokens are shortlived and not saved in db, they are only cryptographically verified
  def create_access_token(user, refresh_token_db) do
    Loginservice.Auth.Guardian.encode_and_sign(user, %{name: user.name, email: user.email, superadmin: user.superadmin, refresh: refresh_token_db.id}, token_type: "access", ttl: {Application.get_env(:loginservice, :ttl_access), :seconds})
  end

  # Fetch a user from DB
  def authenticate_user(username, plain_text_password) do
    query = from u in User, where: u.name == ^username or u.email == ^username

    with user <- Repo.one(query),
      {:ok, _user} <- check_password(user, plain_text_password),
      :ok <- check_active(user),
    do: {:ok, user}
  end

  defp check_password(nil, _) do
    # Even if user wasn't found perform a dummy pw check to make timing attacks more difficult
    # Which in the end is utter bullshit because there is an endpoint to check for user existence...
    Comeonin.Bcrypt.dummy_checkpw
    {:error, "Incorrect username or password"}
  end

  defp check_password(user, plain_text_password) do
    case Comeonin.Bcrypt.checkpw(plain_text_password, user.password) do
      true -> {:ok, user}
      false -> {:error, "Incorrect username or password"}
    end
  end

  defp check_active(user) do
    case user.active do
      true -> :ok
      false -> {:error, "User not activated"}
    end
  end

  def trigger_password_reset(email) do
    user = get_user_by_email!(email)

    with {:ok, password_reset, url} <- create_password_reset_object(user),
         {:ok} <- send_password_reset_mail(user, url),
    do: {:ok, password_reset}
  end

  defp create_password_reset_object(user) do
    url = Loginservice.random_url()

    res = %PasswordReset{}
    |> PasswordReset.changeset(%{url: url, user_id: user.id})
    |> Repo.insert()

    case res do
      {:ok, password_reset} -> {:ok, password_reset, url}
      res -> res
    end
  end

  defp send_password_reset_mail(user, token) do
    url = Application.get_env(:loginservice, :url_prefix) <> "/password_reset?token=" <> token
    Loginservice.Interfaces.Mail.send_mail(user.email, "Reset your password", 
      "To reset your password, visit " <> url <> " or copy&paste this token into the input on the website: " <> token)
  end

  def get_password_reset_by_url!(reset_url) do
    hash = Loginservice.hash_without_salt(reset_url)

    Repo.get_by!(PasswordReset, url: hash)
    |> Repo.preload([:user])
  end

  def execute_password_reset(reset_url, password) do
    password_reset = get_password_reset_by_url!(reset_url)

    res = password_reset.user
    |> User.changeset(%{password: password})
    |> Repo.update()

    if Kernel.elem(res, 0) == :ok do
      Repo.delete!(password_reset)
    end

    res
  end
end
