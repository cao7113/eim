defmodule Eim.StubExtensionOidc do
  @moduledoc false

  def exchange(_code, _state, _nonce, _verifier, _redirect_uri) do
    Application.fetch_env!(:eim, :extension_oidc_stub_result)
  end
end
