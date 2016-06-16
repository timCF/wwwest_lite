defmodule WwwestLite.WebServer do
	use Silverb, 	[
						{"@port", (  res = :application.get_env(:wwwest_lite, :server_port, nil); true = (is_integer(res) and (res > 0)); res  )},
						{"@routes", [
										{"/crossdomain.xml", WwwestLite.WebServer.CrossDomain, []},
										{"/[...]", WwwestLite.WebServer.Handler, []}
									]}
					]
	@compiled_routes :cowboy_router.compile([_: @routes])
	def start do
		case :cowboy.start_http(:wwwest_lite, 5000, [port: @port], [env: [dispatch: @compiled_routes]]) do
			{:ok, _} -> WwwestLite.notice("web listener on port #{@port} started")
			{_, reason} ->
				WwwestLite.error("failed to start listener, reason: #{inspect reason}")
				receive do after 1000 -> nil end
				:erlang.halt
		end
	end
end

defmodule WwwestLite.WebServer.CrossDomain do
	use Silverb, [{"@crossdomain", (case Application.get_env(:wwwest_lite, :crossdomain) do ; true -> true ; false -> false ; nil -> false ; end)}]
	@crossdomainxml ((Exutils.priv_dir(:wwwest_lite)<>"/crossdomain.xml") |> File.read!)

	def terminate(_reason, _req, _state), do: :ok
	def init(_, req, _opts), do: init_proc(req)
	def handle(req, :reply), do: {:ok, req, nil}
	def handle(req, _state), do: init_proc(req)

	case Application.get_env(:wwwest_lite, :crossdomain) do
		true ->
			defp init_proc(req) do
				{:ok, req} = :cowboy_req.reply(200, [{"Content-Type","text/xml; charset=utf-8"},{"Access-Control-Allow-Origin", "*"},{"Connection","Keep-Alive"}], @crossdomainxml, req)
				{:ok, req, :reply}
			end
		no when (no in [false, nil]) ->
			defp init_proc(req) do
				{:ok, req} = :cowboy_req.reply(404, [{"Content-Type","text/xml; charset=utf-8"},{"Connection","Keep-Alive"}], "File not found. Note, crossdomain is not allowed.", req)
				{:ok, req, :reply}
			end
	end
end

defmodule WwwestLite.WebServer.Handler do
	use Silverb, [
					{"@callback_module", ( res = :application.get_env(:wwwest_lite, :callback_module, nil); true = is_atom(res); res  )},
					{"@server_timeout",  ( res = :application.get_env(:wwwest_lite, :server_timeout, nil); true = (is_integer(res) and (res > 0)); res  )},
					{"@post_data_type", Application.get_env(:wwwest_lite, :post_data_type)},
					{"@crossdomain", (case Application.get_env(:wwwest_lite, :crossdomain) do ; true -> true ; false -> false ; nil -> false ; end)}
				 ]

	#
	#	priv
	#

	case {@post_data_type, @crossdomain} do
		{:json, false} -> defp reply_headers, do: [{"Content-Type","application/json; charset=utf-8"},{"Connection","Keep-Alive"}]
		{:json, true} -> defp reply_headers, do: [{"Content-Type","application/json; charset=utf-8"},{"Connection","Keep-Alive"},{"Access-Control-Allow-Origin", "*"}]
		{:xml, false} -> defp reply_headers, do: [{"Content-Type","text/xml; charset=utf-8"},{"Connection","Keep-Alive"}]
		{:xml, true} -> defp reply_headers, do: [{"Content-Type","text/xml; charset=utf-8"},{"Connection","Keep-Alive"},{"Access-Control-Allow-Origin", "*"}]
		{:any, false} -> defp reply_headers, do: [{"Connection","Keep-Alive"}]
		{:any, true} -> defp reply_headers, do: [{"Connection","Keep-Alive"},{"Access-Control-Allow-Origin", "*"}]
	end
	defp reply(ans, req) do
		{:ok, req} = :cowboy_req.reply(200, reply_headers, ans, req)
		{:ok, req, :reply}
	end

	defmacrop options_macro(req) do
		case Application.get_env(:wwwest_lite, :crossdomain) do
			true ->
				quote location: :keep do
					{headers, req} = unquote(req) |> :cowboy_req.headers
					headers = Enum.map(headers, fn({k,v}) ->
						case String.downcase(k) do
							"access-control-request-method" -> {"access-control-allow-method",v}
							"access-control-request-headers" -> {"access-control-allow-headers",v}
							_ -> {k,v}
						end
					end)
					{:ok, req} = :cowboy_req.reply(200, ([{"Access-Control-Allow-Origin", "*"},{"Connection","Keep-Alive"}]++headers), "", req)
					{:ok, req, :reply}
				end
			no when (no in [false, nil]) ->
				quote location: :keep do
					{:ok, req} = :cowboy_req.reply(404, reply_headers, "", req)
					{:ok, req, :reply}
				end
		end
	end

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
		case :cowboy_req.method(req) do
			{"OPTIONS", req} ->
				options_macro(req)
			_ ->
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

end
