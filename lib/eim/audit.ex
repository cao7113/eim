defmodule Eim.Audit do
  use Ash.Domain, otp_app: :eim, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Eim.Audit.Event
  end
end
