defmodule Exbox.Evaluator do

  def evaluate(string, namespace) when is_binary string do
    evaluate namespaced string, namespace
  end
  def evaluate(quoted_code) when is_tuple quoted_code do
    { result, _binding } = Code.eval_quoted(
      quoted_code,
      aliases: [],
      requires: [],
      functions: [],
      macros: []
    )
    result
  end

  defp namespaced(string, namespace) when is_binary string do
    { :ok, quoted_code } = Code.string_to_quoted(string)
    do_namespace quoted_code, namespace
  end

# Recursively walk the ast, looking for module references it can namespace.
# TODO: Probably should make this tail-recursive...
# TODO: Make ast traveral and manipulation library
  defp do_namespace({ :__aliases__, meta, aliases }, namespace) do
    {
      :__aliases__,
      meta,
      Module.split(namespace) ++ aliases
    }
  end
  defp do_namespace({ token, meta, args }, namespace) when is_list args do
    {
      do_namespace(token, namespace),
      meta,
      Enum.map(args, &do_namespace(&1, namespace))
    }
  end
  defp do_namespace({ token, meta, args, kwargs }, namespace) when is_list args and is_list kwargs do
    {
      do_namespace(token, namespace),
      meta,
      Enum.map(args, &do_namespace(&1, namespace)),
      Enum.map(kwargs, &do_namespace(&1, namespace))
    }
  end
  defp do_namespace(list, namespace) when is_list list do
    Enum.map(list, &do_namespace(&1, namespace))
  end
  defp do_namespace({ key, value }, namespace) when is_atom key do
    { key, do_namespace(value, namespace) }
  end
  defp do_namespace(quoted_code, _namespace) do
    quoted_code
  end

end
