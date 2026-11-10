defmodule Eim.Dict do
  use Ash.Domain, otp_app: :eim, extensions: [AshJsonApi.Domain, AshAdmin.Domain]

  admin do
    show? true
  end

  json_api do
    routes do
      route Eim.Dict.Lexeme, :get, "/dict/lookup", :lookup
    end
  end

  resources do
    resource Eim.Dict.Lexeme
    resource Eim.Dict.LexemeForm
    resource Eim.Dict.Import
  end
end
