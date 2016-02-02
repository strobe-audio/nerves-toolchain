defmodule Mix.Tasks.Compile.NervesToolchain do
  use Mix.Task
  import Mix.NervesToolchain.Utils
  require Logger

  @moduledoc """
  Build Nerves Toolchain
  """

  @recursive true

  def run(args) do
    config = Mix.Project.config
    toolchain = config[:app]

    {:ok, _} = Application.ensure_all_started(:nerves_toolchain)
    {:ok, _} = Application.ensure_all_started(toolchain)

    toolchain_config = Application.get_all_env(toolchain)

    target_tuple = toolchain_config[:target_tuple] ||
      raise "Target tuple required to be set in toolchain env"

    nerves_toolchain_config = Application.get_all_env(:nerves_toolchain)
    |> Enum.into(%{})

    cache     = nerves_toolchain_config[:cache]
    compiler  = nerves_toolchain_config[:compiler] || :local

    target = config[:app_path]
    |> Path.join("toolchain")

    stale =
      if (File.dir?(target)) do
        src =  Path.join(File.cwd!, "src")
        sources = src
        |> File.ls!
        |> Enum.map(& Path.join(src, &1))

        Mix.Utils.stale?(sources, [target])
      else
        true
      end
    if stale do
      Mix.shell.info "==> Compile Nerves Toolchain"
      toolchain_tar =
        case cache(cache, %{tuple: target_tuple, username: "nerves", version: config[:version]}) do
          {:ok, toolchain_tar} -> toolchain_tar
          _ -> compile(compiler, target_tuple: target_tuple)
        end
      build(toolchain_tar, target_tuple, config)
    end
    System.put_env("NERVES_TOOLCHAIN", target)
  end

  defp cache(:bakeware, params) do
    Application.ensure_all_started(:bake)
    Mix.shell.info "==> Checking Bakeware Cache"
    case Bake.Api.Toolchain.get(params) do
      {:ok, %{status_code: code, body: body} = resp} when code in 200..299 ->
        cache_response(Poison.decode!(body, keys: :atoms))
      {_, result} -> {:error, result}
    end
  end

  defp cache(_), do: {:error, :nocache}

  defp cache_response(%{data: %{host: host, path: path}}) do
    case Bake.Api.request(:get, "#{host}/#{path}", []) do
      {:ok, %{status_code: code, body: body}} when code in 200..299 ->
        Mix.shell.info "==> Using Bakeware Cache"
        {:ok, body}
      {_, result} -> {:error, result}
    end
  end

  defp compile(:local, params) do
    Mix.shell.info "==> Starting Nerves Toolchain Build"
    Mix.shell.info "      Host Platform: #{host_platform}"
    Mix.shell.info "      Host Arch: #{host_arch}"
    Mix.shell.info "      Target Tuple: #{params[:target_tuple]}"

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

    System.cmd("sh", ["build.sh", ctng_config], stderr_to_stdout: true, cd: toolchain_src, into: IO.stream(:stdio, :line))
  end

  defp build(toolchain_tar, target_tuple, config) do
    tar_dir = config[:app_path]
    tar_file = tar_dir <> "/toolchain.tar.gz"
    write_result = File.write(tar_file, toolchain_tar)
    System.cmd("tar", ["xf", tar_file], cd: tar_dir)
    File.rm!(tar_file)
    toolchain_dir = Enum.find(File.ls!(tar_dir), &(String.contains?(&1, target_tuple)))
    target = Path.join(tar_dir, "toolchain")
    File.rm_rf!(target)
    rename = File.rename(Path.join(tar_dir, toolchain_dir), target)
    File.touch(target)
  end

end
