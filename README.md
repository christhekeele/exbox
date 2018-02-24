Exbox
=====

Exbox is a Sandboxing library for Elixir. It allows you to build a safe environment and run untrusted Elixir code in it.

*STATUS:* **unmaintained**

This is an outdated initial proof of concept for a project that went with spinning up containers and running untrusted code there instead. The approach I took here—scanning the AST against a whitelist of allowed function calls—is an okay start but can be subverted in several ways, and doesn't prevent other insidious ways arbitrary programs can affect your system.

The white-list metaprogramming itself is a little outdated, too—these days I would run the code through `:elixir_expand.expand/2` so you don't have to deal with things like aliases yourself, then scan through it with `Macro.prewalk/2` to validate against your whitelist.

How It Works
------------

- Step 1:

  The developer creates an empty module (traditionally named `Sandbox`). Using an Exbox provided DSL (`Exbox.Sandbox.Behaviour`), they declare what modules and functions they want to `allow` in the sandbox.

  The `allow` macro defines proxy modules and functions that call out to the real ones.

  They can also treat the sandbox like any other module and add nested modules or custom functions to it.

- Step 2:

  The developer spins up an `Exbox.Server` and adds it in to their application. This server accepts strings of code and passes them to a worker that invokes the `Exbox.Evaluator` with the string of code and sandbox.

  Haven't really built any of step 2 out yet; it's standard OTP and didn't need to make it in to the proof of concept.

- Step 3:

  The `Exbox.Evaluator` converts the code into an abstract syntax tree and traverses it, namespaces all function calls under the provided sandbox module, and evaluates the result. Only whitelisted, proxied function calls in the sandbox succeed; everything else throws an `UndefinedFunctionError`.

Usage
-----

Since the library isn't properly set up with an application, supervisor, or server, you have to clone the code and run `iex -S mix` from the repo directory to play with it.

It assumes you have Elixir 0.10.4-dev.

### Defining a sandbox

```elixir
defmodule My.Sandbox do
  use Exbox.Sandbox.Behaviour
  allow String, [reverse: 1]
  allow IO, [puts: 1]
  allow Enum, :all
end
```

### Evaluating code in a sandbox

```elixir
Exbox.Evaluator.evaluate '''
  IO.puts "Hello World!"
''', My.Sandbox

#=>> Hello World!
#=> :ok

Exbox.Evaluator.evaluate '''
  "!ycnaf" |> String.reverse
''', My.Sandbox

#=> "fancy!"

Exbox.Evaluator.evaluate '''
  "!ycnaf" |> String.reverse |> String.capitalize
''', My.Sandbox

#=>> ** (UndefinedFunctionError) undefined function:
#=>>    Exbox.Sandbox.String.capitalize/1:
#=>>    Exbox.Sandbox.String.capitalize("fancy!")

Exbox.Evaluator.evaluate '''
  defmodule Foo do
    def bar do
      IO.puts "baz"
    end
  end
  Foo.bar
''', My.Sandbox

#=>> baz
#=> :ok

Exbox.Evaluator.evaluate '''
  defmodule Danger do
    def zone do
      File.rm_rf "/"
    end
  end
  Danger.zone
''', My.Sandbox

#=>> ** (UndefinedFunctionError) undefined function:
#=>>    Exbox.Sandbox.File.rm_rf/1:
#=>>    Exbox.Sandbox.File.rm_rf("/")
```

Notes
-----

I think this is a pretty cool approach to a sandbox. There isn't a lot of code in Exbox right now, but getting the metaprogramming and ast traversal to work took a lot of tinkering. There's a lot left to do, but I think things will go faster with this core proof of concept down.

By effectively symlinking whitelisted functions into a clean namespace and forcing remote code execution into that context, actual library code can run unaffected. Disabling remote users from writing to the filesystem does not mean breaking a whitespaced function that relies on that ability.

On the other hand, that means you have to have a very good idea of what it is you're whitelisting. Also worth noting is that while it will be possible to exclude functions from an allowed module with `allow File, except: [rm_rf: 1]`, a true blacklisted mode where you don't have to explictly allow modules you're not worried about is non-trivial in Elixir.

This is because while introspection on a module is easy, introspection on the list of available modules isn't.

To mitigate this inconvenience, one of the top priorities in the To Do section below is to provide various sandbox behaviour helpers that bring in pre-prepared, cultivated sets of functions.

To Do
-----

- Start testing this code
- Set up Server behaviour
- Make Server timeout configurable
- Set up Application behaviour so other Elixir projects can easily use it
- Allow Application configuration to influence if one-off Servers should be spun up on demand, or have a dedicated configurable set that's kept running
- Have the Evaluator return bindings that can be persisted in a dedicated Server's state in between evaluation, effectively allowing persistent remote Elixir runtimes
- Make exceptions properly bubble up from the Evaluator to the Server, so OTP can handle it accordingly
- Define custom helpers to `allow` grouped, cultivated sets of functions
- Allow sandboxes to be configured with 'taint levels', that can further filter the set of allowed functions
- Create a record for storing taint levels and grouping tags of a module's functions
- Use these records to build an index of Elixir core's functions
- Document using these records so other 3rd party libraries can maintain their own
- Investigate custom context-aware module attributes similar to `@doc` that would enable 3rd party library developers to more easily specify the tags and taint levels of their functions
- Write tests for and prevent undesirable access to top-level directives (like require) and meta-programming exploits

AST Transformation
------------------

```elixir
####
# INPUT CODE:
##
  defmodule Foo do
    def bar do
      String.capitalize "hello"
    end
  end
  Foo.bar

####
# QUOTED CODE:
##
  { :__block__, [line: 1], [
    {:defmodule, [line: 1], [
      {:__aliases__, [line: 1], [:Foo]}, [ #<<<=== convert to [:My, :Sandbox, :Foo]
        do: {:def, [line: 2], [
          {:bar, [line: 2], nil}, [
            do: {
              {:., [line: 3], [
                {:__aliases__, [line: 3], [:String]}, #<<<=== convert to [:My, :Sandbox, :String]
                :capitalize
              ] },
            [line: 3], ["hello"]
          } ]
        ] }
      ]
    ] },
    {
      {:., [line: 6], [
        {:__aliases__, [line: 6], [:Foo]}, #<<<=== convert to [:My, :Sandbox, :Foo]
        :bar
      ] },
      [line: 6], []
    }
  ] }

####
# EFFECTIVE CODE:
##
  defmodule My.Sandbox.Foo do
    def bar do
      My.Sandbox.String.capitalize "hello"
    end
  end
  My.Sandbox.Foo.bar
```
