defmodule Mix.NervesToolchain.Utils do

  def host_arch do
    {arch, 0} = System.cmd("uname", ["-m"])
    arch
    |> String.strip
    |> String.downcase
  end

  def host_platform do
    {platform, 0} = System.cmd("uname", ["-s"])
    platform
    |> String.strip
    |> String.downcase
  end

end
