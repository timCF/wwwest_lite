defmodule WwwestLite do
  use Application
  use Silverb, [{"@memo_ttl", (  res = :application.get_env(:wwwest_lite, :memo_ttl, nil); true = (is_integer(res) and (res > 0)); res  )}]
  use Logex, [ttl: 100]

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      # Define workers and child supervisors to be supervised
      # worker(WwwestLite.Worker, [arg1, arg2, arg3])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WwwestLite.Supervisor]
    res = Supervisor.start_link(children, opts)
    WwwestLite.WebServer.start
    res
  end

  def encode(some), do: Tinca.memo(&Jazz.encode!/1, [some], @memo_ttl)
  def decode(some), do: Tinca.memo(&Jazz.decode!/2, [some, [keys: :atoms]], @memo_ttl)
  def decode_safe(some), do: Tinca.memo(&Jazz.decode/2, [some, [keys: :atoms]], @memo_ttl)

  defmacro callback_module([do: body]) do
    quote location: :keep do
      unquote(body)
      def handle_wwwest_lite(_), do: "{\"error\":\"bad request\"}"
    end
  end

end
