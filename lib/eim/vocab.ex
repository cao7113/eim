defmodule Eim.Vocab do
  use Ash.Domain, otp_app: :eim, extensions: [AshJsonApi.Domain, AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Eim.Vocab.Entry
  end
end
