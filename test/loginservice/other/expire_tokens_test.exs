defmodule Loginservice.ExpireTokensTest do
  use Loginservice.DataCase

  alias Loginservice.Auth.PasswordReset
  alias Loginservice.Auth.RefreshToken
  alias Loginservice.Registration.MailConfirmation

  @valid_user_attrs %{email: "some@email.com", name: "some name", password: "some password", active: true}
  @valid_campaign_attrs %{active: true, callback_url: "some callback_url", name: "some name", url: "some_url", description_short: "some description", description_long: "some long description"}

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(@valid_user_attrs)
      |> Loginservice.Auth.create_user()

    user
  end

  def submission_fixture(user) do
    {:ok, campaign} = Loginservice.Registration.create_campaign(@valid_campaign_attrs)
    attrs = %Loginservice.Registration.Submission{responses: "ast", user_id: user.id, campaign_id: campaign.id}
    Repo.insert!(attrs)
  end

  def token_fixture(time \\ Ecto.DateTime.utc()) do
    user = user_fixture()
    submission = submission_fixture(user)

    reset = %PasswordReset{}
    |> PasswordReset.changeset(%{user_id: user.id, url: "bla"})
    |> Ecto.Changeset.force_change(:inserted_at, time)
    |> Repo.insert!()

    confirmation = %MailConfirmation{}
    |> MailConfirmation.changeset(%{submission_id: submission.id, url: "bla"})
    |> Ecto.Changeset.force_change(:inserted_at, time)
    |> Repo.insert!()

    refresh = %RefreshToken{}
    |> RefreshToken.changeset(%{user_id: user.id, token: "bla", device: "bla"})
    |> Ecto.Changeset.force_change(:inserted_at, time)
    |> Repo.insert!()

    %{reset: reset, confirmation: confirmation, refresh: refresh, submission: submission, user: user}
  end

  test "expire tokens worker leaves useful tokens intact" do
    token_fixture() 
    
    Loginservice.ExpireTokens.handle_info(:work, {})

    assert Repo.all(MailConfirmation) != []
    assert Repo.all(PasswordReset) != []
    assert Repo.all(RefreshToken) != []
  end


  test "expire tokens worker removes outdated tokens" do
    Loginservice.ecto_date_in_past(Application.get_env(:loginservice, :ttl_refresh) * 2)
    |> token_fixture()

    Loginservice.ExpireTokens.handle_info(:work, {})    

    assert Repo.all(MailConfirmation) == []
    assert Repo.all(PasswordReset) == []
    assert Repo.all(RefreshToken) == []
  end

  test "expire tokens workers also removes users and submissions in case a mail confirmation expired" do
    %{submission: submission, user: user} = Loginservice.ecto_date_in_past(Application.get_env(:loginservice, :ttl_refresh) * 2)
    |> token_fixture()

    Loginservice.ExpireTokens.handle_info(:work, {})    

    assert_raise Ecto.NoResultsError, fn -> Repo.get!(Loginservice.Registration.Submission, submission.id) end
    assert_raise Ecto.NoResultsError, fn -> Repo.get!(Loginservice.Auth.User, user.id) end
  end

  test "mail confirmation expiry worker tries to delete member objects from core" do
    %{user: user} = Loginservice.ecto_date_in_past(Application.get_env(:loginservice, :ttl_refresh) * 2)
    |> token_fixture()

    assert {:ok, user} = Loginservice.Auth.update_user_member_id(user, 1)

    :ets.insert(:core_fake_responses, {:member_delete, {:ok}})

    {deletes, fails} = Loginservice.ExpireTokens.expire_mail_confirmations()
    assert fails == []
    assert deletes != []

    assert_raise Ecto.NoResultsError, fn -> Repo.get!(Loginservice.Auth.User, user.id) end
  end

  test "mail confirmation expiry worker does not delete users for which the member can't be deleted" do
    %{user: user} = Loginservice.ecto_date_in_past(Application.get_env(:loginservice, :ttl_refresh) * 2)
    |> token_fixture()

    assert {:ok, _user} = Loginservice.Auth.update_user_member_id(user, 1)

    :ets.insert(:core_fake_responses, {:member_delete, {:not_found, "This is a test output, we actually want this to appear."}})

    {deletes, fails} = Loginservice.ExpireTokens.expire_mail_confirmations()
    assert fails != []
    assert deletes == []

    assert Repo.get!(Loginservice.Auth.User, user.id)
  end
end