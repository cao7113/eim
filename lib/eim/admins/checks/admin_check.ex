defmodule Eim.Admins.Checks.AdminCheck do
  @moduledoc """
  Authorizes the actor when it is a current administrator.

  Used by the `Eim.Admins.Admin` policies, by administrator-only reads on
  `Eim.Accounts.User` and by `Eim.Audit.Event`. The lookup runs against the
  database, so a stale actor never carries access that was withdrawn.
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "the actor is a current administrator"

  @impl true
  def match?(%Eim.Accounts.User{} = actor, _context, _opts), do: Eim.Admins.admin?(actor)

  def match?(_, _, _), do: false
end
