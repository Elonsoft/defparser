defmodule Defparser do
  @moduledoc """
  Provides a way to define a parser for an arbitrary map with atom or string keys.

  Works with `Ecto.Schema`s and `Ecto.Type`s.

  ## Example

      iex(1)> defmodule Test do
      ...(1)>   import Defparser
      ...(1)>   defparser :user, %{
      ...(1)>     username: %{first_name: :string, last_name: :string},
      ...(1)>     birthdate: :date,
      ...(1)>     favourite_numbers: [%{value: :integer}]
      ...(1)>   }
      ...(1)> end
      iex(2)> Test.parse_user(%{
      ...(2)>   username: %{first_name: "User", last_name: "Name"},
      ...(2)>   birthdate: "1990-01-01",
      ...(2)>   favourite_numbers: [%{value: 1}, %{value: 2}]
      ...(2)> })
      {:ok,
       %{
         __struct__: DefparserTest.Test.User,
         username: %{
           __struct__: DefparserTest.Test.User.Username,
           first_name: "User",
           last_name: "Name"
         },
         birthdate: ~D[1990-01-01],
         favourite_numbers: [
           %{
             __struct__: DefparserTest.Test.User.FavouriteNumbers,
             value: 1
           },
           %{
             __struct__: DefparserTest.Test.User.FavouriteNumbers,
             value: 2
           }
         ]
       }}

  ## Ecto.Type

  You can provide an `Ecto.Type` as a field

      iex(1)> defmodule AtomEctoType do
      ...(1)>   @behaviour Ecto.Type
      ...(1)>   def type, do: :string
      ...(1)>   def cast(str), do: {:ok, String.to_atom(str)}
      ...(1)>   def load(_), do: :error
      ...(1)>   def dump(_), do: :error
      ...(1)>   def embed_as(_), do: :error
      ...(1)>   def equal?(a, b), do: a == b
      ...(1)> end
      iex(2)> defmodule Parser do
      ...(2)>   import Defparser
      ...(2)>   defparser :data, %{atom: AtomEctoType}
      ...(2)> end
      iex(3)> Parser.parse_data(%{atom: "atom"})
      {:ok,
       %{
         __struct__: DefparserTest.Parser.Data,
         atom: :atom
       }}

  ## Ecto.Schema

  You may want to pass already existing ecto schema

      iex(1)> defmodule Schema do
      ...(1)>   use Ecto.Schema
      ...(1)>   @primary_key false
      ...(1)>   embedded_schema do
      ...(1)>     field :x, :integer
      ...(1)>   end
      ...(1)>   def changeset(schema, attrs) do
      ...(1)>     Ecto.Changeset.cast(schema, attrs, [:x])
      ...(1)>   end
      ...(1)> end
      iex(2)> defmodule SchemaParser do
      ...(2)>   import Defparser
      ...(2)>   defparser :data, %{schema: {:embeds_one, Schema}}
      ...(2)> end
      iex(3)> SchemaParser.parse_data(%{schema: %{x: "1"}})
      {:ok,
       %{
         __struct__: DefparserTest.SchemaParser.Data,
         schema: %{
           __struct__: DefparserTest.Schema,
           x: 1
         }
       }}

  Besides `:embeds_one` it supports `:embeds_many` in case you expect
  an array with the provided schema.
  """

  @doc """
  Defines a parser for arbitrary map.
  """
  defmacro defparser(name, schema) do
    {schema_definition, _} = Code.eval_quoted(schema, [], __CALLER__)

    [{root, _} | _] =
      schemas =
      __CALLER__.module
      |> base_namespace(name)
      |> fetch_schemas(schema_definition)

    schemas
    |> Enum.map(&define_module/1)
    |> Enum.each(&Code.compile_quoted(&1))

    quote do
      def unquote(:"parse_#{name}")(attrs) do
        struct!(unquote(root))
        |> unquote(root).changeset(attrs)
        |> Ecto.Changeset.apply_action(:insert)
      end
    end
  end

  defp base_namespace(module, name) do
    Module.concat([module, "#{Macro.camelize(to_string(name))}"])
  end

  defp fetch_schemas(namespace, map) do
    {array_keys, rest} = fetch_arrays(map)
    {schema_keys, value_keys} = fetch_maps(rest)

    arrays =
      fetch_all_schemas(
        namespace,
        Enum.map(array_keys, fn {k, [s]} -> {k, s} end)
      )

    schemas = fetch_all_schemas(namespace, schema_keys)
    values = {namespace, schema_with_embeds(value_keys, arrays, schemas)}

    [values] ++
      Enum.flat_map(arrays, fn {_, _, s} -> s end) ++
      Enum.flat_map(schemas, fn {_, _, s} -> s end)
  end

  defp fetch_arrays(map) do
    Enum.split_with(map, fn
      {_, [_]} -> true
      {_, _} -> false
    end)
  end

  defp fetch_maps(map) do
    Enum.split_with(map, fn {_, x} -> is_map(x) end)
  end

  defp fetch_all_schemas(namespace, schemas) do
    Enum.map(schemas, fn {k, s} ->
      {
        k,
        namespace,
        fetch_schemas(modulename_for_embed(namespace, k), s)
      }
    end)
  end

  defp schema_with_embeds(values, arrays, schemas) do
    values ++
      build_embeds_map(arrays, :embeds_many) ++
      build_embeds_map(schemas, :embeds_one)
  end

  defp build_embeds_map(list, as) do
    for {key, namespace, _schema} <- list do
      {key, {as, modulename_for_embed(namespace, key)}}
    end
  end

  defp modulename_for_embed(namespace, key) do
    Module.concat(namespace, Macro.camelize("#{key}"))
  end

  defp define_module({module, schema}) do
    quote do
      defmodule unquote(module) do
        use Ecto.Schema

        @primary_key false
        embedded_schema do
          unquote(schema_body(schema))
        end

        def changeset(%__MODULE__{} = schema, attrs) do
          unquote(__MODULE__).__schema_changeset__(
            schema,
            attrs,
            unquote(schema_fields(schema)),
            unquote(schema_assocs(schema))
          )
        end
      end
    end
  end

  defp schema_body(schema) do
    for {key, type} <- schema do
      case type do
        {:embeds_one, ref} ->
          quote do
            embeds_one unquote(key), unquote(ref)
          end

        {:embeds_many, ref} ->
          quote do
            embeds_many unquote(key), unquote(ref)
          end

        type when is_atom(type) ->
          quote do
            field unquote(key), unquote(type)
          end
      end
    end
  end

  defp schema_fields(schema) do
    for {key, type} <- schema, is_atom(type), do: key
  end

  defp schema_assocs(schema) do
    for {key, type} <- schema, assoc?(type), do: key
  end

  defp assoc?({_, _}), do: true
  defp assoc?(_), do: false

  @doc false
  def __schema_changeset__(schema, attrs, fields, assocs) do
    changeset = Ecto.Changeset.cast(schema, attrs, fields)

    Enum.reduce(assocs, changeset, fn assoc, changeset ->
      Ecto.Changeset.cast_embed(changeset, assoc)
    end)
  end
end
