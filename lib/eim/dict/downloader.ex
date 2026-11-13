defmodule Eim.Dict.Downloader do
  require Logger

  @base_url "https://raw.githubusercontent.com/skywind3000/ECDICT/39cfb9672c0906b63569e0453c2e6abfb9ab182a"
  @default_url "#{@base_url}/ecdict.csv"
  @mini_url "#{@base_url}/ecdict.mini.csv"

  def default_url, do: @default_url
  def mini_url, do: @mini_url

  def download(url \\ @default_url) do
    uri = URI.parse(url)

    unless uri.scheme in ["http", "https"] and is_binary(uri.host) do
      raise ArgumentError, "invalid ECDICT download URL: #{url}"
    end

    segments = String.split(uri.path || "", "/", trim: true)
    file_name = List.last(segments) || "ecdict.csv"
    commit = Enum.at(segments, -2)

    commit_suffix =
      if commit && Regex.match?(~r/\A[0-9a-f]{7,40}\z/i, commit), do: "-#{commit}", else: ""

    name = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    extension = Path.extname(file_name)
    basename = Path.rootname(file_name, extension)
    path = Path.join(System.tmp_dir!(), "#{basename}#{commit_suffix}-#{name}#{extension}")
    partial_path = path <> ".part"
    file = File.open!(partial_path, [:write, :binary, :exclusive])

    Logger.info("Downloading ECDICT from #{url} to file: #{path}")

    try do
      response =
        try do
          Req.get!(url,
            retry: false,
            receive_timeout: 600_000,
            into: fn {:data, data}, {request, response} ->
              if response.status == 200, do: :ok = IO.binwrite(file, data)
              {:cont, {request, response}}
            end
          )
        after
          :ok = File.close(file)
        end

      unless response.status == 200 do
        raise "ECDICT download failed with HTTP status #{response.status}"
      end

      File.rename!(partial_path, path)
      path
    after
      case File.rm(partial_path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> raise File.Error, reason: reason, action: "remove", path: partial_path
      end
    end
  end
end
