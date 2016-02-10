defmodule Mix.Tasks.Compile.NervesToolchain do
  use Mix.Task
  import Mix.NervesToolchain.Utils
  require Logger

  @moduledoc """
  Build Nerves Toolchain
  """

  @recursive true
  @switches [cache: :string]
  @recv_timeout 120_000

  def run(args) do
    Mix.shell.info "Compile Nerves toolchain"

    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    config = Mix.Project.config
    toolchain = config[:app]
    {:ok, _} = Application.ensure_all_started(:nerves_toolchain)
    {:ok, _} = Application.ensure_all_started(toolchain)

    toolchain_config = Application.get_all_env(toolchain)

    target_tuple = toolchain_config[:target_tuple] ||
      raise "Target tuple required to be set in toolchain env"

    nerves_toolchain_config = Application.get_all_env(:nerves_toolchain)
    |> Enum.into(%{})

    cache       = opts[:cache] || nerves_toolchain_config[:cache] || :github
    cache       = if is_binary(cache), do: String.to_atom(cache), else: cache
    app_path    = Mix.Project.app_path(config)
    params      = %{target_tuple: target_tuple, version: config[:version], app_path: app_path}

    if stale?(app_path) do
      toolchain   = cache(cache, params)
      toolchain
      |> copy_build(params)
    else
      Mix.shell.info "Nerves toolchain up to date"
    end

    Mix.shell.info "Update environment for toolchain"
    System.put_env("NERVES_TOOLCHAIN", app_path)
  end

  defp stale?(app_path) do
    app_path = app_path
    |> Path.join("toolchain")
    if (File.dir?(app_path)) do
      src =  Path.join(File.cwd!, "src")
      sources = src
      |> File.ls!
      |> Enum.map(& Path.join(src, &1))

      Mix.Utils.stale?(sources, [app_path])
    else
      true
    end
  end

  defp cache(:github, params) do
    Mix.shell.info "Downloading from Github Cache"
    Application.ensure_all_started(:httpoison)

    url = "https://github.com/nerves-project/nerves-toolchain/releases/download/v#{params.version}/nerves-#{params.target_tuple}-#{host_platform}-#{host_arch}-v#{params.version}.tar.xz"
    case HTTPoison.get(url, [], follow_redirect: true, recv_timeout: @recv_timeout) do
      {:ok, %{status_code: code, body: body}} when code in 200..299 -> body
      {_, error} ->
        raise "Nerves Toolchain Github cache returned error: #{inspect error}"
    end
  end

  defp cache(:none, params) do
    compile(params)
  end

  defp compile(params) do
    Mix.shell.info "Starting Nerves Toolchain Build"
    Mix.shell.info "  Host Platform: #{host_platform}"
    Mix.shell.info "  Host Arch: #{host_arch}"
    Mix.shell.info "  Target Tuple: #{params[:target_tuple]}"

    nerves_toolchain = Mix.Dep.loaded([])
    |> Enum.find(fn
      %{app: :nerves_toolchain} -> true
      _ -> false
    end)

    toolchain_src = nerves_toolchain
    |> Map.get(:opts)
    |> Keyword.get(:dest)
    toolchain_src = toolchain_src <> "/src"
    ctng_config = File.cwd! <> "/src/#{host_platform}.config"

    result = System.cmd("sh", ["build.sh", ctng_config], stderr_to_stdout: true, cd: toolchain_src, into: IO.stream(:stdio, :line))
    case result do
      {_, 0} -> File.read!(toolchain_src <> "/toolchain.tar.xz")
      {error, _} -> raise "Error compiling toolchain: #{inspect error}"
    end
  end

  defp copy_build(toolchain_tar, params) do
    Mix.shell.info "Unpacking toolchain to build dir"
    tar_dir = params.app_path
    tar_file = tar_dir <> "/toolchain.tar.xz"
    write_result = File.write(tar_file, toolchain_tar)
    System.cmd("tar", ["xf", tar_file], cd: tar_dir)
    File.rm!(tar_file)
    toolchain_dir = Enum.find(File.ls!(tar_dir), &(String.contains?(&1, params.target_tuple)))
    target = Path.join(tar_dir, "toolchain")
    rename = File.rename(Path.join(tar_dir, toolchain_dir), target)
    File.touch(target)
  end

end
