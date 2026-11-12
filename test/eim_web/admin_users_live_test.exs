defmodule EimWeb.AdminUsersLiveTest do
  use EimWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Eim.Accounts.User
  alias Eim.Accounts.Admins, as: AdminRoles

  test "only administrators can manage roles and revoked sessions lose access", %{conn: conn} do
    alice = create_user("alice-admin@example.com")
    bob = create_user("bob-admin@example.com")
    assert {:ok, _} = AdminRoles.bootstrap("alice-admin@example.com")

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/manage/users")
    assert {:error, {:redirect, %{to: "/"}}} = live(signed_in_conn(bob), "/manage/users")

    {:ok, view, _} = live(signed_in_conn(alice), "/manage/users")

    view
    |> form("#admin-user-search", search: %{email: "bob-admin@example.com"})
    |> render_submit()

    assert has_element?(view, "#admin-selected-user", "user")
    view |> element("#admin-toggle-role") |> render_click()
    assert has_element?(view, "#admin-selected-user", "admin")
    assert AdminRoles.admin?(bob.id)

    assert {:ok, _} = AdminRoles.set_role(bob.id, alice.id, :user)

    assert {:error, {:redirect, %{to: "/"}}} =
             view
             |> form("#admin-user-search", search: %{email: "bob-admin@example.com"})
             |> render_submit()
  end

  defp create_user(email) do
    {:ok, password} = AshAuthentication.BcryptProvider.hash("password123456")

    Ash.Seed.seed!(User, %{
      email: email,
      hashed_password: password,
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
