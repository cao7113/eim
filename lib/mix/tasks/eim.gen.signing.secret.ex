defmodule Mix.Tasks.Eim.Gen.Signing.Secret do
  use Mix.Task

  @shortdoc "Generates a token signing secret"
  @moduledoc """
  Generates a random secret for `TOKEN_SIGNING_SECRET` and prints it to stdout.

      mix eim.gen.signing.secret

  Store the output securely and keep it stable across application restarts.
  Changing the secret invalidates existing signed tokens.
  """

  @impl Mix.Task
  def run([]) do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
    |> Mix.shell().info()
  end

  def run(_args), do: Mix.raise("usage: mix eim.gen.signing.secret")
end
