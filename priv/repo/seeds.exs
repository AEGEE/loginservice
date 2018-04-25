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

  Repo.insert!(%User{
    name: "nico",
    email: "nico.westerbeck@aegee.eu",
    active: true,
    id: 11
  } |> User.changeset(%{password: "nico1234"}))

  Repo.insert!(%User{
    name: "sergey",
    email: "sergey@aegee.org",
    active: true,
    id: 12
  } |> User.changeset(%{password: "sergey1234"}))
end