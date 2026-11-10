defmodule Mix.Tasks.Eim.ImportEcdict do
  use Mix.Task

  @shortdoc "Imports an ECDICT CSV into the dictionary database"
  @default_path "_local/ecdict/ecdict.csv"

  @impl Mix.Task
  def run(args) do
    {opts, paths, invalid} = OptionParser.parse(args, strict: [version: :string])

    if invalid != [] or length(paths) > 1 do
      Mix.raise("usage: mix eim.import_ecdict [CSV_PATH] [--version SOURCE_VERSION]")
    end

    path =
      case paths do
        [path] -> Path.expand(path)
        [] -> Path.expand(@default_path, File.cwd!())
      end

    unless File.regular?(path) do
      Mix.raise("ECDICT CSV not found: #{path}")
    end

    Mix.Task.run("app.start")

    version = opts[:version] || git_version(path)
    checksum = sha256(path)
    counts = Eim.Dict.Importer.run(path, version)

    notes =
      if counts.skipped_rows == 0 do
        nil
      else
        "Skipped #{counts.skipped_rows} blank or malformed CSV rows"
      end

    Eim.Dict.Import
    |> Ash.Changeset.for_create(:record, %{
      source: "ecdict",
      source_version: version,
      file_sha256: checksum,
      row_count: counts.row_count,
      notes: notes
    })
    |> Ash.create!(domain: Eim.Dict)

    Mix.shell().info(
      "Imported #{counts.row_count} ECDICT rows (#{counts.skipped_rows} skipped), version #{version}, sha256 #{checksum}"
    )
  end

  defp sha256(path) do
    path
    |> File.stream!(1_048_576, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp git_version(path) do
    case System.cmd("git", ["-C", Path.dirname(path), "rev-parse", "HEAD"],
           stderr_to_stdout: true
         ) do
      {version, 0} ->
        String.trim(version)

      {_error, _status} ->
        "unknown"
    end
  end
end
