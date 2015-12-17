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
					{"@server_timeout",  ( res = :application.get_env(:wwwest_lite, :server_timeout, nil); true = (is_integer(res) and (res > 0)); res  )},
					{"@post_data_type", Application.get_env(:wwwest_lite, :post_data_type)}
				 ]
	#
	#	public
	#

	# purge message
	def info({:json, _, _}, req, state), do: {:ok, req, state}
	def terminate(_,_,_), do: :ok
	def init(_,req,_), do: init_func(req)
	def handle(req, :reply), do: {:ok, req, nil}
	def handle(req, _), do: init_func(req)
	defp init_func(req) do
		case :cowboy_req.has_body(req) do
			# GET
			false -> init_proc(req)
			# GET + POST
			true ->  {:ok, req_body, req} = :cowboy_req.body(req)
					 case WwwestLite.decode_post(req_body) do
					 	{:ok, term = %{}} -> init_proc(req, term)
					 	error -> %{error: "Error on decoding req #{inspect error}"} |> WwwestLite.encode |> reply(req)
					 end
		end
	end
	defp init_proc(req, from_body \\ %{}) do
		{qs,req} = :cowboy_req.qs_vals(req)
		Enum.reduce(qs, %{}, fn({k,v},acc) -> Map.put(acc, Maybe.to_atom(k), v) end)
		|> Map.merge(from_body)
		|> run_request(req)
	end
	defp run_request(client_req = %{}, req) do
		daddy = self()
		spawn(fn() -> send(daddy, {:json, client_req, @callback_module.handle_wwwest_lite(client_req)}) end)
		receive do
			{:json, ^client_req, json} -> reply(json, req)
		after
			@server_timeout ->
				{:ok, req} = :cowboy_req.reply(408, reply_headers, "", req)
				{:ok, req, :reply}
		end
	end
	#
	#	priv
	#
	case @post_data_type do
		:json -> defp reply_headers, do: [{"Content-Type","application/json; charset=utf-8"},{"Connection","Keep-Alive"}]
		:xml -> defp reply_headers, do: [{"Content-Type","text/xml; charset=utf-8"},{"Connection","Keep-Alive"}]
		:any -> defp reply_headers, do: [{"Connection","Keep-Alive"}]
	end
	defp reply(ans, req) do
		{:ok, req} = :cowboy_req.reply(200, reply_headers, ans, req)
		{:ok, req, :reply}
	end
end
