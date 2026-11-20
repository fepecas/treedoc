defmodule Crdt.Causal do
  @moduledoc """
  Causal delivery with vector clocks: apply, wait or drop (CLS, DES4, DES4.1, DES4.2).
  Pure module: no processes, network or files. A missing clock key counts as 0.
  """

  @doc """
  Candidate `{seq, vc}` for a local operation at `me`, without side effects (REQ4, DES4.1).
  The caller keeps the new clock only if `Treedoc.prepare/3` returns `{:ok, _}`.
  """
  def next_local(vc, me) do
    seq = get(vc, me) + 1
    {seq, Map.put(vc, me, seq)}
  end

  @doc "True if `msg` was already applied: m[i] <= vc[i] (REQ10, DES4.2)."
  def duplicate?(vc, msg), do: get(msg.vc, msg.from) <= get(vc, msg.from)

  @doc "True if m[i] == vc[i] + 1 and m[k] <= vc[k] for every other node k (REQ9, DES4.2)."
  def deliverable?(vc, msg) do
    get(msg.vc, msg.from) == get(vc, msg.from) + 1 and
      Enum.all?(msg.vc, fn {k, n} -> k == msg.from or n <= get(vc, k) end)
  end

  @doc """
  REQ9, REQ10: applies, buffers or drops `msg`, then drains the buffer (CLS, DES4.2).
  `state` is `%{vc: _, buffer: _, doc: _}`; returns `{state, events}` in order.
  """
  def receive_message(state, msg, apply_fun) do
    {state, event} = step(state, msg, apply_fun)
    {state, events} = drain(state, apply_fun)
    {state, [event | events]}
  end

  defp step(state, msg, apply_fun) do
    cond do
      # REQ10: drop duplicates
      duplicate?(state.vc, msg) ->
        {state, {:duplicate, msg}}

      deliverable?(state.vc, msg) ->
        doc = apply_fun.(state.doc, msg)
        vc = Map.put(state.vc, msg.from, get(msg.vc, msg.from))
        {%{state | doc: doc, vc: vc}, {:applied, msg}}

      # REQ9: wait for the missing dependencies
      true ->
        {buffer_put(state, msg), {:waiting, msg, missing(state.vc, msg)}}
    end
  end

  # DES4.2: take out the first buffered message that is ready or duplicate; repeat
  defp drain(state, apply_fun) do
    ready = fn msg -> duplicate?(state.vc, msg) or deliverable?(state.vc, msg) end

    case Enum.find(state.buffer, ready) do
      nil ->
        {state, []}

      msg ->
        state = %{state | buffer: List.delete(state.buffer, msg)}
        {state, event} = step(state, msg, apply_fun)
        {state, events} = drain(state, apply_fun)
        {state, [event | events]}
    end
  end

  # DES4.2: at most one copy per {from, m[from]}
  defp buffer_put(state, msg) do
    if Enum.any?(state.buffer, &same_op?(&1, msg)),
      do: state,
      else: %{state | buffer: state.buffer ++ [msg]}
  end

  defp same_op?(a, b), do: a.from == b.from and get(a.vc, a.from) == get(b.vc, b.from)

  @doc "What `msg` still needs, as `%{node => last seq}`; m[i] - 1 for the sender (REQ17, DES4.2)."
  def missing(vc, msg) do
    for {k, n} <- msg.vc,
        need = if(k == msg.from, do: n - 1, else: n),
        need > get(vc, k),
        into: %{},
        do: {k, need}
  end

  defp get(vc, k), do: Map.get(vc, k, 0)
end
