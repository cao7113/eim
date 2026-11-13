defmodule Eim.Dict.ImporterTest do
  use Eim.DataCase, async: false

  alias Eim.Dict.{Downloader, Importer, Lexeme, LexemeForm, Lookup}
  alias Eim.Repo
  alias Mix.Tasks.Eim.Ecdict.Download, as: DownloadTask
  alias Mix.Tasks.Eim.Ecdict.Import, as: ImportTask

  @fixture Path.expand("../../support/fixtures/ecdict_sample.csv", __DIR__)

  test "imports rows idempotently and resolves inflected words" do
    assert %{row_count: 4, skipped_rows: 1} = Importer.run(@fixture)
    assert %{row_count: 4, skipped_rows: 1} = Importer.run(@fixture)

    assert Repo.aggregate(Lexeme, :count) == 4
    assert Repo.aggregate(LexemeForm, :count) == 5

    assert Enum.count(
             Repo.all(Eim.Dict.Import),
             &(&1.source_path == @fixture and &1.row_count == 4)
           ) ==
             2

    assert Enum.all?(
             Repo.all(Eim.Dict.Import),
             &(is_integer(&1.duration_ms) and &1.duration_ms >= 0)
           )

    expected_hash = :crypto.hash(:sha256, File.read!(@fixture)) |> Base.encode16(case: :lower)

    assert Enum.all?(
             Repo.all(Eim.Dict.Import),
             &(&1.source_path == @fixture and &1.source_sha256 == expected_hash)
           )

    assert {:ok, entry} = Lookup.run("gave")
    assert entry.lemma == "give"
    assert entry.match == :exact

    assert entry.senses == [
             %{pos: "vt", domain: nil, zh: "给，授予"},
             %{pos: "vi", domain: nil, zh: "让步"}
           ]

    assert {:ok, entry} = Lookup.run("hyphenword")
    assert entry.lemma == "hyphen-word"
    assert entry.match == :fuzzy
  end

  test "downloads a file independently and imports it by local path" do
    commit = "39cfb9672c0906b63569e0453c2e6abfb9ab182a"
    url = serve_csv(200, File.read!(@fixture), "/#{commit}/ecdict.mini.csv")
    path = ExUnit.CaptureIO.capture_io(fn -> DownloadTask.run([url]) end) |> String.trim()
    on_exit(fn -> File.rm!(path) end)

    assert Path.dirname(path) == Path.expand(System.tmp_dir!())
    assert Path.basename(path) =~ "ecdict.mini-#{commit}-"
    assert File.read!(path) == File.read!(@fixture)
    assert %{row_count: 4, skipped_rows: 1} = Importer.run(path)
    assert Repo.aggregate(Lexeme, :count) == 4
    assert Enum.all?(Repo.all(Lexeme), &(&1.source == path))

    assert Repo.get_by!(Eim.Dict.Import, source_path: path).source_sha256 ==
             :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

    assert File.exists?(path)
  end

  test "mix task records each import with its absolute file path" do
    relative_path = Path.relative_to_cwd(@fixture)

    for source <- [relative_path, relative_path] do
      ExUnit.CaptureIO.capture_io(fn ->
        ImportTask.run([source])
      end)
    end

    imports = Repo.all(Eim.Dict.Import)
    assert length(imports) == 2

    assert Enum.count(imports, &(&1.source_path == @fixture)) == 2
    assert Enum.all?(imports, &is_binary(&1.source_sha256))
    assert Enum.all?(imports, &(is_integer(&1.duration_ms) and &1.duration_ms >= 0))
    assert Repo.aggregate(Lexeme, :count) == 4
    assert Enum.all?(Repo.all(Lexeme), &(&1.source == @fixture))
  end

  test "mix task rejects removed version options" do
    assert_raise Mix.Error, ~r/usage:/, fn ->
      ImportTask.run([@fixture, "--version", "old"])
    end
  end

  test "import requires a local file path" do
    assert_raise ArgumentError, ~r/requires a local file path/, fn ->
      Importer.run("https://example.com/ecdict.csv")
    end

    assert_raise Mix.Error, ~r/usage:/, fn -> ImportTask.run([]) end
    assert_raise Mix.Error, ~r/usage:/, fn -> DownloadTask.run(["--unknown"]) end
    assert Repo.aggregate(Eim.Dict.Import, :count) == 0
  end

  test "HTTP errors remove incomplete downloads and do not import" do
    prefix = "eim-error-test-#{System.unique_integer([:positive])}"
    url = serve_csv(404, "not found", "/#{prefix}.csv")

    assert_raise RuntimeError, ~r/ECDICT download failed with HTTP status 404/, fn ->
      Downloader.download(url)
    end

    refute Enum.any?(File.ls!(System.tmp_dir!()), &String.starts_with?(&1, prefix))
    assert Repo.aggregate(Lexeme, :count) == 0
    assert Repo.aggregate(Eim.Dict.Import, :count) == 0
  end

  defp serve_csv(status, body, path) do
    plug = fn conn, _opts ->
      Plug.Conn.send_resp(conn, status, body)
    end

    pid = start_supervised!({Bandit, plug: plug, port: 0, ip: {127, 0, 0, 1}})
    {:ok, {_address, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}#{path}"
  end
end
