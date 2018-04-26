# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Loginservice.Repo.insert!(%Loginservice.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Loginservice.Registration.Campaign
alias Loginservice.Auth.User
alias Loginservice.Repo

if Repo.all(Campaign) == [] do

  Repo.insert!(%Campaign{
    name: "Default recruitment campaign",
    url: "default",
    active: true,
    description_short: "Signup to our app!",
    description_long: "Really, sign up to our app!"
  })

  Repo.insert!(%User{
    name: "admin",
    email: "admin@aegee.org",
    active: true,
    superadmin: true,
    id: 1
  } |> User.changeset(%{password: "admin1234"}))


  # By manually using ids we need to update the primary key sequence to not run into random errors later on
  qry = "SELECT setval('users_id_seq', (SELECT MAX(id) from \"users\"));"
  Ecto.Adapters.SQL.query!(Repo, qry, [])

end