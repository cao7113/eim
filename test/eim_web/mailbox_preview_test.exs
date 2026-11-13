defmodule EimWeb.MailboxPreviewTest do
  use EimWeb.ConnCase, async: false

  alias Eim.Accounts.{Admins, User}

  setup do
    original_config = Application.get_env(:swoosh, :local)

    on_exit(fn ->
      if is_nil(original_config) do
        Application.delete_env(:swoosh, :local)
      else
        Application.put_env(:swoosh, :local, original_config)
      end
    end)

    :ok
  end

  test "mailbox preview requires an admin and Swoosh local mode", %{conn: conn} do
    member = create_user("mailbox-member@example.com")
    admin = create_user("mailbox-admin@example.com")
    assert {:ok, _} = Admins.bootstrap(to_string(admin.email))

    Application.put_env(:swoosh, :local, true)

    assert redirected_to(get(conn, "/mailbox/preview")) == "/"
    assert redirected_to(get(signed_in_conn(member), "/mailbox/preview")) == "/"
    assert response(get(signed_in_conn(admin), "/mailbox/preview"), 200)

    Application.put_env(:swoosh, :local, false)

    assert response(get(signed_in_conn(admin), "/mailbox/preview"), 404) == "Not Found"
  end

  defp create_user(email) do
    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash("password123456")

    Ash.Seed.seed!(User, %{
      email: email,
      hashed_password: hashed_password,
      confirmed_at: DateTime.utc_now()
    })
  end

  defp signed_in_conn(user) do
    strategy = AshAuthentication.Info.strategy!(User, :password)

    {:ok, authenticated} =
      AshAuthentication.Strategy.action(strategy, :sign_in, %{
        email: user.email,
        password: "password123456"
      })

    build_conn()
    |> init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(authenticated)
  end
end
