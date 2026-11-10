defmodule EimWeb.DictJsonApiTest do
  use EimWeb.ConnCase

  @fixture Path.expand("../support/fixtures/ecdict_sample.csv", __DIR__)

  setup do
    Eim.Dict.Importer.run(@fixture, "test-version")
    :ok
  end

  test "GET /api/dict/lookup returns dictionary results", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> get("/api/dict/lookup?text=gave")

    assert %{
             "kind" => "word",
             "match" => "exact",
             "lemma" => "give",
             "senses" => [%{"pos" => "vt", "zh" => "给，授予"}, %{"pos" => "vi", "zh" => "让步"}]
           } = json_response(conn, 200)
  end

  test "GET /api/dict/lookup includes misses in the declared response shape", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> get("/api/dict/lookup?text=unknownword")

    assert %{
             "match" => "miss",
             "lemma" => nil,
             "senses" => [],
             "tags" => [],
             "sources" => []
           } = json_response(conn, 200)
  end

  test "GET /api/dict/lookup returns JSON:API errors for invalid input", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> get("/api/dict/lookup?text=#{String.duplicate("a", 501)}")

    assert %{"errors" => [%{"detail" => detail}]} = json_response(conn, 400)
    assert detail =~ "length"
  end

  test "lookup action is included in the unified OpenAPI spec", %{conn: conn} do
    conn = get(conn, "/api/open_api")
    spec = conn |> response(200) |> Jason.decode!()
    operation = spec["paths"]["/api/dict/lookup"]["get"]
    assert is_map(operation)
    assert Enum.any?(operation["parameters"], &(&1["name"] == "text"))

    senses_schema =
      operation["responses"]["200"]["content"]["application/vnd.api+json"]["schema"]["properties"][
        "senses"
      ]

    assert Enum.any?(senses_schema["anyOf"], &(&1["items"]["type"] == "object"))
  end
end
