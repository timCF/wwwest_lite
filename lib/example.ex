defmodule WwwestLite.Example do
	require WwwestLite
	WwwestLite.callback_module do
		def handle_wwwest_lite(%{cmd: "echo", args: some}), do: %{ans: some} |> WwwestLite.encode
		def handle_wwwest_lite(%{cmd: "time"}), do: %{ans: Exutils.makestamp} |> WwwestLite.encode
	end
end