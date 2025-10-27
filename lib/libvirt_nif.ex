defmodule LibvirtNif do
  require Logger

  @on_load :load_nifs

  def load_nifs do
    # Try multiple methods to find the NIF
    paths_to_try = [
      # Standard location
      :filename.join(:code.priv_dir(:vm_monitoring), ~c"libvirt_nif"),
      # Absolute path (for debugging)
      ~c"#{File.cwd!()}/priv/libvirt_nif",
      # Alternative
      Path.join([__DIR__, "..", "..", "priv", "libvirt_nif"]) |> String.to_charlist()
    ]

    Enum.reduce_while(paths_to_try, {:error, :not_found}, fn path, _acc ->
      Logger.info("Trying to load NIF from: #{path}")
      so_file = "#{path}.so"
      Logger.info("Checking if #{so_file} exists: #{File.exists?(so_file)}")

      case :erlang.load_nif(path, 0) do
        :ok ->
          Logger.info("✅ NIF loaded successfully from: #{path}")
          {:halt, :ok}

        {:error, {reason, text}} ->
          Logger.warning("❌ Failed to load from #{path}: #{reason} - #{text}")
          {:cont, {:error, reason}}
      end
    end)
  end

  @type conn :: reference()   # or whatever your C side produces

  @spec connect(uri :: charlist()) :: {:ok, conn} | {:error, charlist() | :badarg}
  def connect(_uri) do
    :erlang.nif_error(:nif_not_loaded)
  end

  def disconnect(_conn) do
    raise "NIF disconnect/1 not loaded"
  end

  # @spec list_domains(conn) :: {:ok, [String.t()]} | {:error, charlist()}
  # def list_domains(_conn) do
  #   # raise "NIF list_domains/1 not loaded"
  #   :erlang.nif_error(:nif_not_loaded)
  # end

  # @type domain :: %{
  #       id: integer(),
  #       name: String.t(),
  #       memory: integer(),      # bytes
  #       cpu_time: integer(),    # whatever unit you return
  #       state: String.t()
  #     }

  # @spec list_domains(conn) :: {:ok, [domain]} | {:error, charlist()}

  @type domain :: %{
        id: integer(),
        name: String.t(),
        memory: integer(),
        cpu_time: integer(),
        state: String.t()
      }

  @spec list_domains(conn()) :: {:ok, [domain()]} | {:error, charlist()}
  def list_domains(_conn) do
    :erlang.nif_error(:nif_not_loaded)
  end


  @type cpu_time :: %{
        total: non_neg_integer(),
        idle: non_neg_integer(),
        user: non_neg_integer(),
        kernel: non_neg_integer()
      }

  @type host :: %{
    time: [cpu_time()],
    cpus: non_neg_integer()
  }

  @spec get_host_info(conn()) :: {:ok, host()} | {:error, charlist()}
  def get_host_info(_conn) do
    :erlang.nif_error(:nif_not_loaded)
  end
end
