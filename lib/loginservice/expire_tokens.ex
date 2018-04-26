defmodule Loginservice.ExpireTokens do
  use GenServer
  import Ecto.Query, warn: false


  def start_link do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    schedule_work() # Schedule work to be performed at some point
    {:ok, state}
  end

  def handle_info(:work, state) do
    expire_mail_confirmations()
    expire_password_resets()
    expire_refresh_tokens()

    schedule_work() # Reschedule once more
    {:noreply, state}
  end

  def expire_refresh_tokens() do
    expiry = Loginservice.ecto_date_in_past(Application.get_env(:loginservice, :ttl_refresh))
    query = from u in Loginservice.Auth.RefreshToken,
      where: u.inserted_at < ^expiry

    Loginservice.Repo.delete_all(query)
  end

  def expire_mail_confirmations() do
    # Pipeline of death to find a date in the past
    expiry = Loginservice.ecto_date_in_past(Application.get_env(:loginservice, :ttl_mail_confirmation)) 
    query = from u in Loginservice.Registration.MailConfirmation,
      where: u.inserted_at < ^expiry

    # Try to delete as many member objects as possible, save the fails
    {deletes, fails} = query 
    |> Loginservice.Repo.all()
    |> Enum.map(fn(x) -> Loginservice.Repo.preload(x, [submission: [:user]]) end)
    |> Enum.map(fn(x) ->
      member_deletion = if x.submission.user.member_id do
        Loginservice.Interfaces.MemberFetch.delete_member(x.submission.user.member_id)
      else
        {:ok}
      end

      {x, member_deletion}
    end)
    |> Enum.split_with(fn({_, res}) -> res == {:ok} end)
    
    # Deleting the user object will cascade through to submission and mail_confirmation
    deletes = deletes
    |> Enum.map(fn({x, _}) -> 
      Loginservice.Repo.delete(x.submission.user)
    end)

    # Output the fails to command line hoping someone will see it
    fails = fails
    |> Enum.map(fn({x, res}) -> 
      IO.inspect("Could not delete member " <> to_string(x.submission.user.member_id) <> " from core, core responded") 
      IO.inspect(res)
    end)

    {deletes, fails}
  end

  def expire_password_resets() do
    expiry = Loginservice.ecto_date_in_past(Application.get_env(:loginservice, :ttl_password_reset))
    query = from u in Loginservice.Auth.PasswordReset,
      where: u.inserted_at < ^expiry

    Loginservice.Repo.delete_all(query)
  end


  defp schedule_work() do
    Process.send_after(self(), :work, Application.get_env(:loginservice, :expiry_worker_freq)) # Every 5 minutes check for expired stuff
  end
end