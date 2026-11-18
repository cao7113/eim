defmodule EimWeb.AuthLiveTest do
  use EimWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "sign-in page uses the Eim layout and branded authentication styles", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/sign-in")

    assert has_element?(view, "nav[aria-label='Main navigation'] #dictionary-link")
    assert has_element?(view, "div.text-lime-800", "Make every word count.")
    assert has_element?(view, "[type='submit'].bg-slate-950")
    refute has_element?(view, "img[src*='ash-hq.org']")
  end
end
