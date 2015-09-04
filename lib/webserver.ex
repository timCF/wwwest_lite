defmodule WwwestLite.WebServer do
	use Silverb, 	[
						{"@port", (  res = :application.get_env(:wwwest_lite, :server_port, nil); true = (is_integer(res) and (res > 0)); res  )},
						{"@routes", [{"/[...]", WwwestLite.WebServer.Handler, []}]}
					]
	@compiled_routes :cowboy_router.compile([_: @routes])
	def start do
		case :cowboy.start_http(:wwwest_lite, 5000, [port: @port], [env: [dispatch: @compiled_routes]]) do
			{:ok, _} -> WwwestLite.notice("web listener on port #{@port} started")
			{_, reason} ->
				WwwestLite.error("failed to start listener, reason: #{inspect reason}")
				receive do after 1000 -> end
				:erlang.halt
		end
	end
end

defmodule WwwestLite.WebServer.Handler do
	use Silverb, [
					{"@callback_module", ( res = :application.get_env(:wwwest_lite, :callback_module, nil); true = is_atom(res); res  )},
					{"@server_timeout",  ( res = :application.get_env(:wwwest_lite, :server_timeout, nil); true = (is_integer(res) and (res > 0)); res  )}
				 ]
	#
	#	public
	#
	def info({:json, json}, req, state), do: reply(json, req, state)
	def terminate(_reason, _req, _state), do: :ok
	def init(req, _opts), do: init_func(req)
	def handle(req, _state), do: init_func(req)
	defp init_func(req) do
		case :cowboy_req.has_body(req) do
			# GET
			false -> init_proc(req)
			# GET + POST
			true ->  {:ok, req_body, req} = :cowboy_req.body(req)
					 case WwwestLite.decode_safe(req_body) do
					 	{:ok, term = %{}} -> init_proc(req, term)
					 	error -> %{error: "Error on decoding req #{inspect error}"} |> WwwestLite.encode |> reply(req, nil)
					 end
		end	
	end
	defp init_proc(req, from_body \\ %{}) do
		:cowboy_req.parse_qs(req)
		|> Enum.reduce(%{}, fn({k,v},acc) -> Map.put(acc, Maybe.to_atom(k), v) end)
		|> Map.merge(from_body)
		|> run_request(req)
	end
	#
	#	priv
	#
	defp reply(ans, req, state), do: {:ok, :cowboy_req.reply(200, [{"Content-Type","application/json; charset=utf-8"},{"connection","close"}], ans, req), state}
	defp run_request(client_req = %{}, req) do
		daddy = self()
		spawn(fn() -> send(daddy, {:json, @callback_module.handle_wwwest_lite(client_req)}) end)
		{:cowboy_loop, req, nil, @server_timeout}
	end
end