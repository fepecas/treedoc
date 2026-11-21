defmodule CrdtFw do
  @moduledoc """
  Starts the node on a Pi with Nerves, with no start script (REQ21, CON3, DES15): waits for the IPv4
  of wlan0, starts the distribution, then `Crdt.Replica` and `Crdt.Discovery` (REQ14) under
  `CrdtFw.NodeSupervisor`. One job per process (CON5): it starts the node, the supervisor restarts.
  """

  use GenServer

  @addresses ["interface", "wlan0", "addresses"]
  @data_dir "/data/crdt"

  @doc "Starts `CrdtFw`, registered with its module name."
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  # DES15: the steps run after init/1, so CrdtFw.Supervisor is not blocked
  @impl true
  def init(_opts), do: {:ok, :waiting, {:continue, :start}}

  # DES15 step 1: wait for an IPv4 on wlan0; subscribe first, so no change is missed
  @impl true
  def handle_continue(:start, :waiting) do
    VintageNet.subscribe(@addresses)
    ip = ipv4(VintageNet.get(@addresses))
    if ip == nil, do: IO.puts("waiting for an IPv4 on wlan0")
    {:noreply, start_node(ip)}
  end

  @impl true
  def handle_info({VintageNet, @addresses, _old, addresses, _meta}, :waiting),
    do: {:noreply, start_node(ipv4(addresses))}

  # DES15: later changes of the IP are ignored; a new IP needs a restart (REQ13, DES14)
  def handle_info(_message, state), do: {:noreply, state}

  # DES15 assumption: vintage_net gives each IPv4 as a tuple, with family :inet
  defp ipv4(addresses) do
    Enum.find_value(addresses || [], fn a -> if a.family == :inet, do: a.address end)
  end

  # DES15: if a step fails, say which and why, start nothing and stay alive (DES6)
  defp start_node(nil), do: :waiting

  defp start_node(ip) do
    with :ok <- distribution(:"#{hostname()}@#{:inet.ntoa(ip)}"),
         # DES15 step 6: the root file system is read-only; /data is writable
         :ok <- step("mkdir #{@data_dir}", File.mkdir_p(@data_dir)),
         :ok <- wait_for_old(),
         :ok <- step("CrdtFw.NodeSupervisor", start_children()) do
      IO.puts("node: #{node()} (interface: wlan0)")
      :started
    else
      {:error, name, reason} ->
        IO.puts("node not started: step #{name} failed (#{inspect(reason)})")
        :failed
    end
  end

  defp step(_name, :ok), do: :ok
  defp step(_name, {:ok, _pid}), do: :ok
  defp step(name, {:error, reason}), do: {:error, name, reason}

  # DES15 steps 2 to 5, skipped if a restarted CrdtFw finds the node alive
  defp distribution(name) do
    if Node.alive?() do
      :ok
    else
      # DES6, DES15 step 2: fixed ports, read by OTP when the listen socket opens
      Application.put_env(:kernel, :inet_dist_listen_min, 4218)
      Application.put_env(:kernel, :inet_dist_listen_max, 4228)

      # DES15 steps 3 to 5: epmd, long names, the cookie of every node (DES6)
      with :ok <- step("epmd", epmd()),
           :ok <- step("Node.start", Node.start(name, :longnames)) do
        Node.set_cookie(:cpd2026)
        :ok
      end
    end
  end

  # DES15 step 3: Nerves does not start epmd
  defp epmd do
    case System.cmd("epmd", ["-daemon"], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _status} -> {:error, output}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  # DES6, DES15 step 4: the Nerves hostname, nerves-XXXX, made safe for a node name
  defp hostname do
    {:ok, host} = :inet.gethostname()
    host |> List.to_string() |> String.downcase() |> String.replace(~r/[^a-z0-9_-]/, "_")
  end

  # DES15 step 7: an old supervisor or replica may still be stopping after a restart;
  # wait for its :DOWN, so two replicas never write the same .jsonl (DES4.5)
  defp wait_for_old do
    refs =
      for name <- [CrdtFw.NodeSupervisor, Crdt.Replica],
          pid = Process.whereis(name),
          do: Process.monitor(pid)

    step("wait for the old replica", wait_down(refs))
  end

  # DES15 step 7: at most 10 s for each one, then the step fails with :timeout
  defp wait_down([]), do: :ok

  defp wait_down([ref | rest]) do
    receive do
      {:DOWN, ^ref, :process, _pid, _reason} -> wait_down(rest)
    after
      10_000 -> {:error, :timeout}
    end
  end

  # DES15 step 7: the replica, then discovery, one_for_one and linked to CrdtFw (DES8)
  defp start_children do
    nodes = Application.get_env(:crdt_fw, :nodes, [])
    children = [{Crdt.Replica, data_dir: @data_dir, nodes: nodes}, Crdt.Discovery]
    Supervisor.start_link(children, strategy: :one_for_one, name: CrdtFw.NodeSupervisor)
  end
end
