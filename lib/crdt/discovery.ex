defmodule Crdt.Discovery do
  @moduledoc """
  Finds our nodes on the local network: a UDP multicast announcement every 2 s (REQ14, DES6.1).
  Only packets with our tag count; without a socket the node keeps the table only (DES6).
  """

  use GenServer

  @tag "crdt-treedoc-1 "
  @group {233, 252, 1, 32}

  @doc "Options: `:me`, `:ip` and `:port` (docs/DESIGN.md DES8)."
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "`{mode, heard}`: `\"listening on <port>\"` or `\"announce only\"`, and the node names heard."
  def info, do: GenServer.call(__MODULE__, :info)

  @doc "The announcement of `node`: our tag and its name."
  def packet(node), do: @tag <> Atom.to_string(node)

  @doc "`{:ok, node}` if the packet has our tag (DES6.1), `:ignore` otherwise."
  def parse(@tag <> name) when name != "", do: {:ok, String.to_atom(name)}
  def parse(_other), do: :ignore

  @impl true
  def init(opts) do
    me = Keyword.get(opts, :me, node())
    port = Keyword.get(opts, :port, 45892)
    ip = Keyword.get_lazy(opts, :ip, fn -> interface(me) end)

    case open(port, ip) do
      {:ok, socket, mode} ->
        send(self(), :announce)
        {:ok, %{me: me, port: port, socket: socket, mode: mode, heard: MapSet.new()}}

      {:error, reason} ->
        IO.puts(
          "[#{me}] discovery off: cannot open UDP port #{port} " <>
            "(#{:inet.format_error(reason)}). Use a node table (NODES_FILE)."
        )

        :ignore
    end
  end

  # DES6.1: the multicast interface is the IP of the node name, if it is an IPv4
  defp interface(me) do
    [_name, host] = String.split(Atom.to_string(me), "@")
    {result, ip} = :inet.parse_ipv4strict_address(String.to_charlist(host))
    if result == :ok, do: ip, else: {0, 0, 0, 0}
  end

  # DES6.1: one listener per machine; if the port is busy, announce only
  defp open(port, ip) do
    opts = [:binary, active: true, multicast_if: ip, multicast_ttl: 1, multicast_loop: true]

    with {:error, :eaddrinuse} <- listen(port, ip, opts),
         {:ok, socket} <- :gen_udp.open(0, opts),
         do: {:ok, socket, "announce only"}
  end

  defp listen(port, ip, opts) do
    with {:ok, socket} <- :gen_udp.open(port, [add_membership: {@group, ip}] ++ opts),
         do: {:ok, socket, "listening on #{port}"}
  end

  @impl true
  def handle_call(:info, _from, state), do: {:reply, {state.mode, state.heard}, state}

  @impl true
  def handle_info(:announce, state) do
    # a failed send (Wi-Fi down for a moment) is ignored; the next one tries again
    :gen_udp.send(state.socket, @group, state.port, packet(state.me))
    Process.send_after(self(), :announce, 2_000)
    {:noreply, state}
  end

  # DES6.1, DES7.1: ignore our own name and connected nodes; connect in a short-lived process
  def handle_info({:udp, _socket, _ip, _port, data}, state) do
    case parse(data) do
      {:ok, n} when n != state.me ->
        if n not in Node.list(), do: spawn(fn -> Node.connect(n) end)
        {:noreply, %{state | heard: MapSet.put(state.heard, n)}}

      _ ->
        {:noreply, state}
    end
  end
end
