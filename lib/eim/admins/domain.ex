defmodule Eim.Admins.Domain do
  @moduledoc """
  Domain for administrator access records.

  Kept separate from `Eim.Accounts` so that user records hold identity only.
  """

  use Ash.Domain, otp_app: :eim, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Eim.Admins.Admin
  end
end
