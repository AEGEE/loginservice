defmodule LoginserviceWeb.CampaignControllerTest do
  use LoginserviceWeb.ConnCase

  alias Loginservice.Registration
  alias Loginservice.Registration.Campaign
  alias Loginservice.Auth
  alias Loginservice.Repo
  alias Loginservice.Auth.User

  @create_attrs %{active: true, callback_url: "some callback_url", name: "some name", url: "some_url", description_short: "some description", description_long: "some long description"}
  @update_attrs %{active: true, callback_url: "some updated callback_url", name: "some updated name", url: "some_updated_url", description_short: "some other description"}
  @invalid_attrs %{active: nil, callback_url: nil, name: nil, url: nil}
  @valid_user_attrs %{email: "some@email.com", name: "some name", password: "some password", active: true}
  @valid_submission %{name: "some new username", password: "some new password", email: "some@email.com", responses: nil}
  @invalid_submission %{name: nil, password: nil, email: nil, responses: nil}
  @core_create_successful {:ok, %{"user_id" => 1, "id" => 1}}
  @core_create_unsuccessful {:unprocessable_entity, %{"errors" => %{"last_name" => "required"}}}
  @core_delete_successful {:ok}
  @core_delete_unsuccessful {:not_found, "message"}

  def fixture(:campaign) do
    {:ok, campaign} = Registration.create_campaign(@create_attrs)
    campaign
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(@valid_user_attrs)
      |> Auth.create_user()
    user = user
      |> User.changeset(%{})
      |> Ecto.Changeset.force_change(:superadmin, true)
      |> Repo.update!

    {:ok, _user, access_token, _refresh_token} = Auth.login_user(@valid_user_attrs.name, @valid_user_attrs.password)

    {user, access_token}
  end

  def user_fixture_nonadmin(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(@valid_user_attrs)
      |> Auth.create_user()

    {:ok, _user, access_token, _refresh_token} = Auth.login_user(@valid_user_attrs.name, @valid_user_attrs.password)

    {user, access_token}
  end

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all campaigns", %{conn: conn} do
      conn = get conn, campaign_path(conn, :index)
      assert json_response(conn, 200)["data"]
    end
  end

  describe "create campaign" do
    test "renders campaign when data is valid", %{conn: conn} do
      {_user, access_token} = user_fixture()
      conn = put_req_header(conn, "x-auth-token", access_token)

      conn = post conn, campaign_path(conn, :create), campaign: @create_attrs
      assert %{"id" => id} = json_response(conn, 201)["data"]

      conn = conn
      |> recycle()
      |> put_req_header("x-auth-token", access_token)

      conn = get conn, campaign_path(conn, :show, @create_attrs.url)
      assert json_response(conn, 200)["data"] |> map_inclusion(%{
        "id" => id,
        "active" => true,
        "callback_url" => "some callback_url",
        "name" => "some name",
        "url" => "some_url"})
    end

    test "renders errors when data is invalid", %{conn: conn} do
      {_user, access_token} = user_fixture()
      conn = put_req_header(conn, "x-auth-token", access_token)

      conn = post conn, campaign_path(conn, :create), campaign: @invalid_attrs
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "allows only admins to create recruitment campaigns", %{conn: conn} do
      {_user, access_token} = user_fixture_nonadmin()
      conn = put_req_header(conn, "x-auth-token", access_token)

      conn = post conn, campaign_path(conn, :create), campaign: @create_attrs
      assert json_response(conn, 403)
    end
  end

  describe "update campaign" do
    setup [:create_campaign]

    test "renders campaign when data is valid", %{conn: conn, campaign: %Campaign{id: id} = campaign} do
      {_user, access_token} = user_fixture()
      conn = put_req_header(conn, "x-auth-token", access_token)

      conn = put conn, campaign_path(conn, :update, campaign), campaign: @update_attrs
      assert %{"id" => ^id} = json_response(conn, 200)["data"]

      conn = conn
      |> recycle()
      |> put_req_header("x-auth-token", access_token)

      conn = get conn, campaign_path(conn, :show, @update_attrs.url)
      assert json_response(conn, 200)["data"] |> map_inclusion(%{
        "id" => id,
        "active" => true,
        "callback_url" => "some updated callback_url",
        "name" => "some updated name",
        "url" => "some_updated_url"})
    end

    test "renders errors when data is invalid", %{conn: conn, campaign: campaign} do
      {_user, access_token} = user_fixture()
      conn = put_req_header(conn, "x-auth-token", access_token)

      conn = put conn, campaign_path(conn, :update, campaign), campaign: @invalid_attrs
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "allows only admins to update recruitment campaigns", %{conn: conn, campaign: campaign} do
      {_user, access_token} = user_fixture_nonadmin()
      conn = put_req_header(conn, "x-auth-token", access_token)

      conn = put conn, campaign_path(conn, :update, campaign), campaign: @update_attrs
      assert json_response(conn, 403)
    end
  end

  describe "delete campaign" do
    setup [:create_campaign]

    test "deletes chosen campaign", %{conn: conn, campaign: campaign} do
      {_user, access_token} = user_fixture()
      conn = put_req_header(conn, "x-auth-token", access_token)

      conn = delete conn, campaign_path(conn, :delete, campaign)
      assert response(conn, 204)
      
      conn = conn
      |> recycle()
      |> put_req_header("x-auth-token", access_token)

      assert_error_sent 404, fn ->
        get conn, campaign_path(conn, :show, campaign.url)
      end
    end

    test "allows only admins to delete campaigns", %{conn: conn, campaign: campaign} do
      {_user, access_token} = user_fixture_nonadmin()
      conn = put_req_header(conn, "x-auth-token", access_token)

      conn = delete conn, campaign_path(conn, :delete, campaign)
      assert response(conn, 403)
    end
  end

  describe "submit signup" do
    setup [:create_campaign]

    test "a valid submission returns successful status code", %{conn: conn, campaign: campaign} do
      :ets.insert(:core_fake_responses, {:member_create, @core_create_successful})
      :ets.insert(:core_fake_responses, {:member_delete, @core_delete_successful})

      conn = post conn, campaign_path(conn, :submit, campaign.url), submission: @valid_submission
      assert json_response(conn, 201)

      assert user = Auth.get_user_by_email!(@valid_submission.email)
      assert user.name == @valid_submission.name
    end

    test "a valid submission stores the member_id alongside the user", %{conn: conn, campaign: campaign} do
      :ets.insert(:core_fake_responses, {:member_create, @core_create_successful})
      :ets.insert(:core_fake_responses, {:member_delete, @core_delete_successful})

      conn = post conn, campaign_path(conn, :submit, campaign.url), submission: @valid_submission
      assert json_response(conn, 201)

      assert user = Auth.get_user_by_email!(@valid_submission.email)
      assert user.member_id == 1
    end

    test "a invalid submission returns an error", %{conn: conn, campaign: campaign} do
      :ets.insert(:core_fake_responses, {:member_create, @core_create_successful})
      :ets.insert(:core_fake_responses, {:member_delete, @core_delete_successful})

      conn = post conn, campaign_path(conn, :submit, campaign.url), submission: @invalid_submission
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "invalid member data is passed on to the user", %{conn: conn, campaign: campaign} do
      :ets.insert(:core_fake_responses, {:member_create, @core_create_unsuccessful})
      :ets.insert(:core_fake_responses, {:member_delete, @core_delete_unsuccessful})

      conn = post conn, campaign_path(conn, :submit, campaign.url), submission: @valid_submission
      assert json_response(conn, 422)["errors"]["last_name"] == "required"
    end

    test "a valid submission creates a user object, a submission and a mail confirmation in db", %{conn: conn, campaign: campaign} do
      :ets.insert(:core_fake_responses, {:member_create, @core_create_successful})
      :ets.insert(:core_fake_responses, {:member_delete, @core_delete_successful})

      conn = post conn, campaign_path(conn, :submit, campaign.url), submission: @valid_submission
      assert json_response(conn, 201)
      
      user = Repo.get_by(User, name: @valid_submission.name)
      assert user != nil
      assert user.active == false

      submission = Repo.get_by(Loginservice.Registration.Submission, user_id: user.id)
      assert submission != nil
      assert submission.mail_confirmed == false

      mail_confirmation = Repo.get_by(Loginservice.Registration.MailConfirmation, submission_id: submission.id)
      assert mail_confirmation != nil
    end

    test "a valid submission sends a confirmation mail to the user", %{conn: conn, campaign: campaign} do
      :ets.insert(:core_fake_responses, {:member_create, @core_create_successful})
      :ets.insert(:core_fake_responses, {:member_delete, @core_delete_successful})
      :ets.delete_all_objects(:saved_mail)

      conn = post conn, campaign_path(conn, :submit, campaign.url), submission: @valid_submission
      assert json_response(conn, 201)
      assert :ets.lookup(:saved_mail, @valid_submission.email) != []
    end
    
    test "a confirmation mail contains a link over which the user can activate it's account", %{conn: conn, campaign: campaign} do
      :ets.insert(:core_fake_responses, {:member_create, @core_create_successful})
      :ets.insert(:core_fake_responses, {:member_delete, @core_delete_successful})
      :ets.delete_all_objects(:saved_mail)

      conn = post conn, campaign_path(conn, :submit, campaign.url), submission: @valid_submission
      assert json_response(conn, 201)
      
      url = :ets.lookup(:saved_mail, @valid_submission.email)
      |> assert
      |> Enum.at(0)
      |> parse_url_from_mail()

      user = Repo.get_by(User, name: @valid_submission.name)
      assert user != nil
      assert user.active == false

      submission = Repo.get_by(Loginservice.Registration.Submission, user_id: user.id)
      assert submission != nil
      assert submission.mail_confirmed == false

      mail_confirmation = Repo.get_by(Loginservice.Registration.MailConfirmation, submission_id: submission.id)
      assert mail_confirmation != nil
      assert mail_confirmation.url != url # It should be hashed in the db

      conn = recycle(conn)

      conn = post conn, campaign_path(conn, :confirm_mail, url)
      assert json_response(conn, 200)

      # User is active
      user = Repo.get(User, user.id)
      assert user != nil
      assert user.active == true

      # In the submission the mail_confirmed field is true
      submission = Repo.get(Loginservice.Registration.Submission, submission.id)
      assert submission != nil
      assert submission.mail_confirmed == true

      mail_confirmation = Repo.get(Loginservice.Registration.MailConfirmation, mail_confirmation.id)
      assert mail_confirmation == nil
    end
  end

  defp create_campaign(_) do
    campaign = fixture(:campaign)
    {:ok, campaign: campaign}
  end

  defp parse_url_from_mail({_, _, content, _}) do
    # Parse the url token from a content which looks like this:
    # To confirm your email, visit www.alastair.com/registration/signup?token=vXMkHWvQETck73sjQpccFDgQQuavIoDZ

    Application.get_env(:loginservice, :url_prefix) <> "/signup?token="
    |> Regex.escape
    |> Kernel.<>("([^\s]*)")
    |> Regex.compile!
    |> Regex.run(content)
    |> Enum.at(1)
  end
end
