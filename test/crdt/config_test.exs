defmodule Crdt.ConfigTest do
  # Changes the NODES_FILE environment variable, so it does not run async
  use ExUnit.Case, async: false

  alias Crdt.Config

  setup do
    on_exit(fn -> System.delete_env("NODES_FILE") end)
  end

  defp nodes_from(dir, content) do
    path = Path.join(dir, "nodes.txt")
    File.write!(path, content)
    System.put_env("NODES_FILE", path)
    {:ok, ^path, nodes} = Config.nodes()
    nodes
  end

  @tag :req14
  test "without NODES_FILE the table is empty" do
    System.delete_env("NODES_FILE")
    assert Config.nodes() == {:ok, "none", []}
  end

  @tag :req14
  @tag :tmp_dir
  test "skips blank lines and comments and trims spaces", %{tmp_dir: dir} do
    content = "# comment\n\n  a@x  \n   \n#b@x\nc@x"
    assert nodes_from(dir, content) == [:a@x, :c@x]
  end

  @tag :req14
  @tag :tmp_dir
  test "a table with Windows CRLF line endings", %{tmp_dir: dir} do
    content = "# nodes\r\na@x\r\n\r\nb@x\r\n"
    assert nodes_from(dir, content) == [:a@x, :b@x]
  end

  @tag :req14
  test "a missing file is an error with its name" do
    System.put_env("NODES_FILE", "missing_nodes.txt")
    assert Config.nodes() == {:error, "missing_nodes.txt", :enoent}
  end
end
