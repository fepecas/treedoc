# Checks whether this network carries the discovery packets (docs/DESIGN.md, section 6.1).
# Run it at the same time on two or more machines, with no node running:
#   elixir scripts/multicast_check.exs <this machine's IPv4> [seconds]
# The IPv4 is the one that the start script prints. For 30 s (by default) each
# machine sends one packet per second by multicast and by subnet broadcast, and
# prints what arrives from the other machines. Our nodes ignore these packets.

group = {233, 252, 1, 32}
port = 45892

{ip, seconds} =
  case System.argv() do
    [ip] -> {ip, 30}
    [ip, seconds] -> {ip, String.to_integer(seconds)}
    _ -> raise "usage: elixir scripts/multicast_check.exs <this machine's IPv4> [seconds]"
  end

{:ok, me} = :inet.parse_ipv4strict_address(String.to_charlist(ip))

# The subnet broadcast address of the interface that has this IP
{:ok, interfaces} = :inet.getifaddrs()

netmask =
  Enum.find_value(interfaces, fn {_name, opts} ->
    i = Enum.find_index(opts, &(&1 == {:addr, me}))
    i && Keyword.get(Enum.drop(opts, i), :netmask)
  end) || raise "no interface has the IP #{ip}"

broadcast =
  List.to_tuple(
    for i <- 0..3,
        do: Bitwise.bor(elem(me, i), Bitwise.band(Bitwise.bnot(elem(netmask, i)), 255))
  )

options = [
  :binary,
  active: true,
  broadcast: true,
  multicast_if: me,
  multicast_ttl: 1,
  multicast_loop: false,
  add_membership: {group, me}
]

socket =
  case :gen_udp.open(port, options) do
    {:ok, socket} -> socket
    {:error, :eaddrinuse} -> raise "UDP port #{port} is busy: halt the nodes of this machine first"
    {:error, reason} -> raise "cannot open UDP port #{port}: #{:inet.format_error(reason)}"
  end

{:ok, host} = :inet.gethostname()
IO.puts("#{host} #{ip}: sending to #{:inet.ntoa(group)} and #{:inet.ntoa(broadcast)}, port #{port}, for #{seconds} s")

defmodule Check do
  def loop(_socket, _targets, _me, seq, seconds) when seq > seconds, do: :ok

  def loop(socket, targets, me, seq, seconds) do
    {:ok, host} = :inet.gethostname()

    for {kind, address} <- targets do
      :gen_udp.send(socket, address, 45892, "crdt-check|#{host}|#{kind}|#{seq}")
    end

    receive_until(me, System.monotonic_time(:millisecond) + 1_000)
    loop(socket, targets, me, seq + 1, seconds)
  end

  # Prints every check packet that comes from another IP, until `deadline`
  defp receive_until(me, deadline) do
    wait = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:udp, _socket, from, _port, "crdt-check|" <> rest} when from != me ->
        IO.puts("received from #{:inet.ntoa(from)}: #{rest}")
        receive_until(me, deadline)

      {:udp, _socket, _from, _port, _other} ->
        receive_until(me, deadline)
    after
      wait -> :ok
    end
  end
end

Check.loop(socket, [multicast: group, broadcast: broadcast], me, 1, seconds)
IO.puts("Done. If nothing arrived from the other machines, discovery cannot work here: use a node table (NODES_FILE).")
