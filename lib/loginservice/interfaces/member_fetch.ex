defmodule Loginservice.Interfaces.MemberFetch do
  @superadmin_user %{superadmin: true, id: 1, name: "microservice", email: "oms@aegee.eu"}

  defp fake_access_token() do
    {:ok, token, _claims} = Loginservice.Auth.Guardian.encode_and_sign(@superadmin_user, %{name: @superadmin_user.name, email: @superadmin_user.email, superadmin: @superadmin_user.superadmin, refresh: nil}, token_type: "access", ttl: {15, :seconds})
    token  
  end

  def fetch_member(token, member_id) do
    provider = Application.get_env(:loginservice, Loginservice.Interfaces.MemberFetch)[:member_data_provider]
    apply(Loginservice.Interfaces.MemberFetch, provider, [token, member_id])
  end

  def test_fetch(_token, _member_id) do
    {:member_fetch, data} = :ets.lookup(:core_fake_responses, :member_fetch)
    |> Enum.at(0)

    {:ok, data}
  end

  def fetch_from_core(token, member_id) do
    res = HTTPoison.get(Application.get_env(:loginservice, Loginservice.Interfaces.MemberFetch)[:core_url] <> "/members/" <> member_id, 
                        [{"X-Auth-Token", token}, {"Accept", "application/json"}])

    case res do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %HTTPoison.Response{status_code: 403}} -> {:forbidden, "Core returned 403, check your permissions"}
      res -> res
    end
  end

  def delete_member(member_id) do
    provider = Application.get_env(:loginservice, Loginservice.Interfaces.MemberFetch)[:member_delete_provider]
    apply(Loginservice.Interfaces.MemberFetch, provider, [member_id])
  end

  def test_delete(_member_id) do
    {:member_delete, result} = :ets.lookup(:core_fake_responses, :member_delete)
    |> Enum.at(0)

    result
  end

  def delete_from_core(member_id) do
    token = fake_access_token()
    res = HTTPoison.delete(Application.get_env(:loginservice, Loginservice.Interfaces.MemberFetch)[:core_url] <> "/members/" <> to_string(member_id), 
                           [{"X-Auth-Token", token}, {"Accept", "application/json"}, {"Content-Type", "application/json"}])

    res |> IO.inspect
    case res do
      {:ok, %HTTPoison.Response{status_code: 204}} -> {:ok}
      {:ok, %HTTPoison.Response{status_code: 404}} -> {:not_found, "Could not delete member because member_id was not found"}
      {:ok, %HTTPoison.Response{status_code: 403}} -> {:forbidden, "Core didn't accept fake token..."}
      res -> res
    end
  end

  def create_member(member) do
    provider = Application.get_env(:loginservice, Loginservice.Interfaces.MemberFetch)[:member_create_provider]
    apply(Loginservice.Interfaces.MemberFetch, provider, [member])
  end

  def test_create(_member) do
    {:member_create, result} = :ets.lookup(:core_fake_responses, :member_create)
    |> Enum.at(0)

    result
  end

  defp parse_member(body) do
    %{"success" => true, "data" => member} = Poison.decode!(body)
    member
  end

  defp parse_error(body) do
    %{"success" => false, "errors" => errors} = Poison.decode!(body)
    %{errors: errors}
  end

  def create_from_core(member) do
    token = fake_access_token()
    body = Poison.encode!(%{member: member}) |> IO.inspect
    res = HTTPoison.post(Application.get_env(:loginservice, Loginservice.Interfaces.MemberFetch)[:core_url] <> "/members",
                         body, 
                         [{"X-Auth-Token", token}, {"Accept", "application/json"}, {"Content-Type", "application/json"}])

    IO.inspect(res)
    case res do
      {:ok, %HTTPoison.Response{status_code: 201, body: body}} -> {:ok, parse_member(body)}
      {:ok, %HTTPoison.Response{status_code: 422, body: body}} -> {:unprocessable_entity, parse_error(body)}
      {:ok, %HTTPoison.Response{status_code: 403}} -> {:forbidden, "Core didn't accept fake token..."}
      res -> res
    end
  end
end