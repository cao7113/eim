defmodule Mix.Tasks.eim().gen.signing.secretTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.eim().gen.signing.secret

  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)
    :ok
  end

  test "generates independent 256-bit URL-safe secrets" do
    Secret.run([])
    assert_receive {:mix_shell, :info, [first]}
    Secret.run([])
    assert_receive {:mix_shell, :info, [second]}

    assert {:ok, first_bytes} = Base.url_decode64(first, padding: false)
    assert {:ok, second_bytes} = Base.url_decode64(second, padding: false)
    assert byte_size(first_bytes) == 32
    assert byte_size(second_bytes) == 32
    refute first == second
  end

  test "rejects unexpected arguments" do
    assert_raise Mix.Error, "usage: mix eim.gen.signing.secret", fn ->
      Secret.run(["unexpected"])
    end
  end
end
