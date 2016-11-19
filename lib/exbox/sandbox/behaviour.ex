defmodule Exbox.Sandbox.Behaviour do

  defmacro __using__(settings \\ []) do
    quote location: :keep, unquote: false do
      import Exbox.Sandbox.Behaviour, only: [allow: 2]
    end
  end

  defmacro allow(module, signatures \\ :all) do
    quote do

      oldspace = unquote(module)
      namespace = Module.concat __MODULE__, unquote(module)
      signatures = case unquote(signatures) do
        :all  -> oldspace.__info__(:functions)
        _     -> unquote(signatures)
      end

      proxy_functions = Enum.map( signatures,
        fn {func_name, arity} ->

          # Makes placeholder ast function arguments
          args = 0..arity
            |> Enum.map( fn x ->
                { :"arg#{x}", [], nil }
              end )
            |> tl

          quote do
            def unquote(func_name)(unquote_splicing(args)) do
              unquote(oldspace).unquote(func_name)(unquote_splicing(args))
            end
          end

        end
      )

      Module.create namespace, proxy_functions

    end
  end

end
