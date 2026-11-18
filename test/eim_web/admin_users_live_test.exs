defmodule EimWeb.AdminUsersLiveTest do
  use EimWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

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

  defp create_user(email), do: Eim.AccountsFixtures.user_fixture(email)

  defp signed_in_conn(user), do: Eim.AccountsFixtures.signed_in_conn(user)
end
