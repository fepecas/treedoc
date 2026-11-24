defmodule Crdt.DiscoveryTest do
  use ExUnit.Case, async: true

  alias Crdt.Discovery

  @tag :req14
  test "the packet carries our tag and the node name; parse reads it back" do
    packet = Discovery.packet(:"pi-pe@172.20.10.4")
    assert packet == "crdt-treedoc-1 pi-pe@172.20.10.4"
    assert Discovery.parse(packet) == {:ok, :"pi-pe@172.20.10.4"}
  end

  @tag :req14
  test "a packet without our tag, or with the tag and no name, is ignored" do
    for packet <- ["pi-pe@172.20.10.4", "other-tag pi-pe@172.20.10.4", "crdt-treedoc-1 ", ""] do
      assert Discovery.parse(packet) == :ignore
    end
  end

  @tag :req23
  @tag :req14
  test "a tagged name that cannot be an atom is ignored: over 255 bytes or not valid UTF-8" do
    name = String.duplicate("a", 251) <> "@x.y"
    assert Discovery.parse("crdt-treedoc-1 " <> name) == {:ok, String.to_atom(name)}

    for bad <- [String.duplicate("a", 252) <> "@x.y", "pi" <> <<255>> <> "@1.2.3.4"] do
      assert Discovery.parse("crdt-treedoc-1 " <> bad) == :ignore
    end
  end
end
