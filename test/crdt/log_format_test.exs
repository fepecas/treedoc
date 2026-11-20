defmodule Crdt.LogFormatTest do
  use ExUnit.Case, async: true

  alias Crdt.LogFormat

  @a :"crdt1@127.0.0.1"
  @b :"crdt2@127.0.0.1"

  defp ins(ch), do: %{op: :ins, from: @a, vc: %{@a => 3, @b => 1}, pos: [{1, 3, @a}], ch: ch}

  @tag :req18
  test "a line has the format of docs/DESIGN.md DES5.2 and ends in a newline" do
    msg = %{op: :ins, from: @a, vc: %{@a => 3}, pos: [{1, 3, @a}], ch: "a"}

    assert LogFormat.to_json_line(msg) ==
             ~s({"op":"ins","from":"crdt1@127.0.0.1","vc":{"crdt1@127.0.0.1":3},) <>
               ~s("pos":[[1,3,"crdt1@127.0.0.1"]],"ch":"a"}\n)
  end

  @tag :req18
  test "round trip of inserts with ñ, á, a newline and an emoji, and a clock of two nodes" do
    for ch <- ["ñ", "á", "\n", "😀"] do
      line = LogFormat.to_json_line(ins(ch))
      # one op per line: the newline inside the text is escaped
      assert length(String.split(line, "\n")) == 2
      assert LogFormat.from_json_line(line) == {:ok, ins(ch)}
    end
  end

  @tag :req18
  test "round trip of a delete, which has no ch" do
    del = %{op: :del, from: @b, vc: %{@a => 3, @b => 1}, pos: [{1, 3, @a}, {0, 1, @b}]}
    line = LogFormat.to_json_line(del)
    refute line =~ "ch"
    assert LogFormat.from_json_line(line) == {:ok, del}
  end

  @tag :req18
  @tag :req19
  test "garbage, empty text and JSON with another shape are errors, never exceptions" do
    bad = [
      "garbage",
      "",
      ~s({"op":"ins","from":"a@x"),
      "[1, 2]",
      ~s({"op":"move","from":"a@x","vc":{},"pos":[]}),
      ~s({"op":"ins","from":"a@x","vc":{"a@x":1},"pos":[[1,1,"a@x"]]}),
      ~s({"op":"del","from":"a@x","vc":{"a@x":"1"},"pos":[[1,1,"a@x"]]}),
      ~s({"op":"del","from":"a@x","vc":{"a@x":1},"pos":[[2,1,"a@x"]]}),
      ~s({"op":"del","from":"a@x","vc":{"a@x":1},"pos":[[1,1]]}),
      ~s({"op":"del","from":1,"vc":{"a@x":1},"pos":[]})
    ]

    for line <- bad do
      assert {:error, _} = LogFormat.from_json_line(line)
    end
  end
end
