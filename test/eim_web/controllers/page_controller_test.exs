defmodule EimWeb.PageControllerTest do
  use EimWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)

    assert response =~ "Make every word"
    assert response =~ "YOUR WORDS, WORKING FOR YOU"
    assert response =~ "how-it-works"
    refute response =~ "Phoenix Framework"
    refute response =~ ~s(id="dev-tools")
    assert response =~ ~s(id="sign-in-link")
    assert response =~ ~s(href="/auth/user/authx")
  end

  test "GET / displays the signed-in user's email", %{conn: conn} do
    user = Eim.AccountsFixtures.user_fixture("reader@example.com")

    conn =
      conn
      |> init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)
      |> get(~p"/")

    response = html_response(conn, 200)

    assert response =~ ~s(id="current-user-email")
    assert response =~ "reader@example.com"
    assert response =~ ~s(id="user-tools")
    assert response =~ ~s(id="user-tools-toggle")
    assert response =~ ~s(id="user-tools-menu")
    assert response =~ ~s(id="sign-out-link")
    assert response =~ ~s(id="vocabulary-link")
    assert response =~ ~s(href="/learn/vocab")
    assert response =~ "Open Vocabulary"
    refute response =~ ~s(href="/sign-in")
    refute response =~ ~s(id="sign-in-link")
  end
end
