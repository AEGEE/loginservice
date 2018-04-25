defmodule Loginservice.Interfaces.MemberFetch do
  def fetch_member(token, member_id) do
    provider = Application.get_env(:loginservice, Loginservice.Interfaces.MemberFetch)[:member_data_provider]
    apply(Loginservice.Interfaces.MemberFetch, provider, [token, member_id])
  end

  def test_response(_token, _member_id) do
    {:member_fetch, data} = :ets.lookup(:core_fake_responses, :member_fetch)
    |> Enum.at(0)

    {:ok, data}
  end

  def query_core(token, member_id) do
    res = HTTPoison.get("http://oms-core-elixir:4000/members/" <> member_id, [{"X-Auth-Token", token}, {"Accept", "application/json"}])

    case res do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %HTTPoison.Response{status_code: 403}} -> {:forbidden, "Core returned 403, check your permissions"}
      res -> res
    end
  end
end