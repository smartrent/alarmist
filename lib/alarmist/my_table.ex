# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.MyTable do
  @moduledoc """
  A tiny tabular data renderer

  This module renders tabular data in a human-readable format as text. It
  accepts the following types of data:

  ```
  # List of matching maps (atom or string keys)
  data = [
    %{"id" => 1, "name" => "Sherlock"},
    %{"id" => 2, "name" => "John"}
  ]

  # List of matching key-value lists
  data = [
    [{"id", 1}, {"name", "Sherlock"}],
    [{"id", 2}, {"name", "John"}]
  ]
  ```

  See [Table](https://hex.pm/packages/table) for conversions from columnar
  formats.

  To quickly print tabular data, use `puts/2`:

  ```
  data = [%{id: 1, name: "Sherlock"}, %{id: 2, name: "John"}]
  MyTable.puts(data)
  #=> id  name
  #=> 1   Sherlock
  #=> 2   John
  ```

  A typical usage is:

  ```
  iex> data = [
  ...>   %{planet: "Mercury", orbital_period: 88},
  ...>   %{planet: "Venus", orbital_period: 224.701},
  ...>   %{planet: "Earth", orbital_period: 365.256},
  ...>   %{planet: "Mars", orbital_period: 686.971}
  ...> ]
  iex> header = [planet: "Planet", orbital_period: "Orbital Period (days)"]
  iex> MyTable.new()
  ...>    |> MyTable.set_header(header)
  ...>    |> MyTable.set_data(data)
  ...>    |> MyTable.auto_size_columns()
  ...>    |> MyTable.render()
  ...>    |> IO.ANSI.format(false)
  ...>    |> IO.chardata_to_string()
  "Planet   Orbital Period (days)  \n" <>
  "Mercury  88                     \n" <>
  "Venus    224.701                \n" <>
  "Earth    365.256                \n" <>
  "Mars     686.971                \n"
  ```

  Note that normally, you'd call `IO.ANSI.format/2` without passing `false` to
  get colorized output and also call `IO.puts/2` to write to a terminal.

  ## Styling

  Various table output styles are supported by supplying a `:style` function.
  The following are included:

  * `simple_style/3` - a minimal table style with underlined headers (default)
  * `markdown_style/3` - GitHub-flavored markdown table style

  ## Data formatting

  Tabular data from some sources doesn't come as strings or
  `t:IO.ANSI.ansidata/0`.  MyTable converts this data naively to strings. When
  this isn't sufficient, you can either preprocess the data or supply a custom
  `:format` function.

  ## Ansidata

  MyTable takes advantage of `t:IO.ANSI.ansidata/0` everywhere. This makes it
  very easy to apply styling, colorization, and other transformations. However,
  it can be hard to read. It's highly recommended to either call `simplify/1` to
  simplify the output for review or to call `IO.ANSI.format/2` and then
  `IO.puts/2` to print it.

  In a nutshell, `t:IO.ANSI.ansidata/0` lets you create lists of strings to
  print and intermix atoms like `:red` or `:blue` to indicate where ANSI escape
  sequences should be inserted if supported. MyTable actually doesn't know what
  any of the atoms means and passes them through. Elixir's `IO.ANSI` module
  does all of the work. If fact, if you find `IO.ANSI` too limited, then you
  could use an alternative like [bunt](https://hex.pm/packages/bunt) and
  include atoms like `:chartreuse` which its formatter will understand.
  """

  @typedoc "An atom or string that signifies the column"
  @type column_id() :: atom() | String.t()
  @typedoc "One row of data represented in a map"
  @type matching_map() :: %{column_id() => any()}
  @typedoc "One row of data represented as a list of column ID, data tuples"
  @type matching_key_value_list() :: [{column_id(), any()}]
  @typedoc "Row-oriented data"
  @type data() :: [matching_map()] | [matching_key_value_list()]

  @typedoc """
  Styling steps

  Styling runs in stages:

  ## `:header`

  The header row is passed in a list of `{column_id, ansidata}` tuples. It
  should be returned as styled ansidata.

  Styling needs to repeat column headers (or whatever is appropriate) when
  `table.wrap_across` is greater than 1.  Multiple lines on text may be
  returned.  No further styling or processing will be done on the header after
  this step.

  ## `:rows_across`

  Data rows are grouped into a list of horizontally adjacent rows. If
  `table.wrap_across` is 1, then the list has one row. If `table.wrap_across`
  is 2, then the list has two data rows and so on. Each data row is passed as a
  list of `[{column_id, ansidata}]`. It should be returned as styled
  ansidata.

  ## `:footer`

  This step is called with the same data as the `:header` step, but at the end.
  """
  @type styling_step() :: :header | :rows_across | :footer

  @typedoc """
  The styling callback function

  See `t:styling_step/0` for details on the the 3rd argument for each step.
  It's possible to store state in the table struct for future styling calls.
  """
  @type style_function() :: (t(), styling_step(), any() -> {t(), IO.ANSI.ansidata()})

  @typedoc """
  Data format callback function

  This function is used for conversion of tabular data to `t:IO.ANSI.ansidata/0`.
  """
  @type format_function() :: (column_id(), any() -> IO.ANSI.ansidata())

  @typedoc """
  Table renderer state

  Fields:
  * `:header` - the table header to text mappings
  * `:data` - data rows
  * `:column_widths` - a map of column IDs to their widths in characters. `nil` until set.
  * `:columns` - the order of the columns in the table. If `nil`, the columns are determined from the header or data.
  * `:default_column_width` - the default column width in characters
  * `:format` - a function to format the data in the table. The default is to convert everything to strings.
  * `:style` - a function to style the table. The default is to use `simple_style/3`.
  * `:wrap_across` - the number of columns to wrap across in multi-column mode. The default is 1.
  """
  @type t :: %__MODULE__{
          column_widths: %{column_id() => pos_integer()},
          columns: nil | [column_id()],
          data: [matching_map()],
          default_column_width: pos_integer(),
          format: (column_id(), any() -> IO.ANSI.ansidata()),
          header: nil | matching_map(),
          style: style_function(),
          wrap_across: pos_integer()
        }
  defstruct header: nil,
            data: [],
            column_widths: %{},
            columns: nil,
            default_column_width: 20,
            format: &Alarmist.MyTable.default_format/2,
            style: &Alarmist.MyTable.simple_style/3,
            wrap_across: 1

  @doc group: "Easy API"
  @doc """
  Print a table to the console

  Call this to quickly print tabular data to the console. This supports
  all of the options from `new/1` and `:ansi_enabled?` to force the use
  of ANSI escape codes.
  """
  @spec puts(data(), keyword()) :: :ok
  def puts(data, options \\ []) do
    data
    |> to_ansidata(options)
    |> IO.ANSI.format(Keyword.get(options, :ansi_enabled?, IO.ANSI.enabled?()))
    |> IO.write()
  end

  @doc group: "Easy API"
  @doc """
  Render a table as `t:IO.ANSI.ansidata/0`

  This formats tabular data and returns it in a form that can be run through
  `IO.ANSI.format/2` for expansion of ANSI escape codes and then written to
  an IO device.
  """
  @spec to_ansidata(data(), keyword()) :: IO.ANSI.ansidata()
  def to_ansidata(data, options \\ []) do
    new(options)
    |> set_data(data)
    |> auto_size_columns()
    |> render()
  end

  @doc group: "Pipe API"
  @doc """
  Create a new table

  Options:
  * `:columns` - the order of the columns in the table
  * `:default_column_width` - default column width in characters
  * `:format` - if passing non-ansidata, supply a function to apply custom formatting
  * `:header` - the table header to text mappings
  * `:data` - tabular data
  * `:style` - see `t:style/0` for details on styling tables
  * `:wrap_across` - the number of columns to wrap across in multi-column mode
  """
  @spec new(keyword()) :: t()
  def new(options \\ []) do
    simple_opts = Keyword.take(options, [:default_column_width, :format, :style, :wrap_across])

    struct(__MODULE__, simple_opts)
    |> maybe(options, :header, &set_header/2)
    |> maybe(options, :data, &set_data/2)
    |> maybe(options, :columns, &set_columns/2)
  end

  defp maybe(table, options, key, fun) do
    case Keyword.get(options, key) do
      nil -> table
      value -> fun.(table, value)
    end
  end

  @doc group: "Pipe API"
  @doc """
  Set the columns and their order in the table
  """
  @spec set_columns(t(), [column_id()]) :: t()
  def set_columns(%__MODULE__{} = table, columns) when is_list(columns) do
    %{table | columns: columns}
  end

  @doc group: "Pipe API"
  @doc """
  Manually set column widths

  Column widths specified in this map override the default column width. Column
  widths can be set automatically using `auto_size_columns/1`.
  """
  @spec set_column_widths(t(), %{column_id() => pos_integer()}) :: t()
  def set_column_widths(%__MODULE__{} = table, column_widths) when is_map(column_widths) do
    %{table | column_widths: column_widths}
  end

  @doc group: "Pipe API"
  @doc """
  Set the table's header

  This function accepts either a map or keyword list. If a keyword list is
  provided, the order of the keywords specifies the order of the columns in the
  table. If passing a map, either call `set_columns/2` or the columns will be
  sorted alphabetically.
  """
  @spec set_header(t(), matching_map() | matching_key_value_list()) :: t()
  def set_header(%__MODULE__{} = table, header) when is_map(header) do
    %{table | header: header}
  end

  def set_header(%__MODULE__{} = table, header) when is_list(header) do
    columns = Enum.map(header, fn {k, _} -> k end)
    %{table | header: Map.new(header), columns: columns}
  end

  @doc group: "Pipe API"
  @doc """
  Set the data rows in the table

  Only row-oriented data is supported. Data is either a list of matching maps
  or a list of matching key-value lists. Keys are either atoms or strings.
  Values can be any type, but it will be converted to `t:IO.ANSI.ansidata/0` by
  the `format` callback. The default is to simplistically format anything
  that's not already `t:IO.ANSI.ansidata/0`.
  """
  @spec set_data(t(), data()) :: t()
  def set_data(%__MODULE__{} = table, [row | _] = d) when is_map(row), do: %{table | data: d}
  def set_data(%__MODULE__{} = table, d), do: %{table | data: Enum.map(d, &Map.new(&1))}

  @doc group: "Pipe API"
  @doc """
  Render the table and wrap columns horizontally

  Call this if you have lots of rows and not many columns to wrap the table
  across columns.
  """
  @spec set_wrap_across(t(), pos_integer()) :: t()
  def set_wrap_across(table, wrap_across) when is_integer(wrap_across) and wrap_across >= 1 do
    %{table | wrap_across: wrap_across}
  end

  defp fill_in_defaults(table) do
    columns = get_columns(table)
    header = table.header || Enum.sort(columns) |> Enum.map(&{&1, to_string(&1)}) |> Map.new()
    %{table | columns: columns, header: header}
  end

  defp get_columns(table) do
    cond do
      table.columns -> table.columns
      table.header -> Map.keys(table.header)
      table.data -> columns_from_data(table.data)
      true -> []
    end
  end

  defp columns_from_data(data) do
    data |> Enum.reduce(%{}, &Map.merge/2) |> Map.keys() |> Enum.sort()
  end

  @doc group: "Pipe API"
  @doc """
  Automatically size the columns fit the data

  This sets the columns to show and their order if that hasn't been done yet.
  """
  @spec auto_size_columns(t()) :: t()
  def auto_size_columns(table) do
    # Establish columns and headers if not set yet
    table = fill_in_defaults(table)
    format = table.format

    column_widths =
      Enum.map(table.columns, fn col ->
        w =
          Enum.reduce(table.data, visual_length(format.(col, table.header[col])), fn row, acc ->
            max(acc, visual_length(format.(col, row[col])))
          end)

        {col, w}
      end)
      |> Map.new()

    %{table | column_widths: column_widths}
  end

  defp width_of_columns(table, columns) do
    Enum.reduce(columns, 0, fn col, acc ->
      acc + (table.column_widths[col] || table.default_column_width) + 2
    end)
  end

  defp terminal_width() do
    case :io.columns() do
      {:ok, width} -> width
      {:error, _} -> 80
    end
  end

  @doc group: "Pipe API"
  @doc """
  Expand one column to fill the width of the terminal

  If `total_width` is not provided, the current terminal's width is used.
  """
  @spec expand_column(t(), atom(), pos_integer()) :: t()
  def expand_column(table, column_name, total_width \\ terminal_width()) do
    columns = get_columns(table)

    if column_name not in columns do
      raise ArgumentError,
            "Column #{column_name} not found in table. Available columns: #{inspect(columns)}"
    end

    new_width = max(8, total_width - width_of_columns(table, columns -- [column_name]))

    new_columns_widths = Map.put(table.column_widths, column_name, new_width)

    %{table | columns: columns, column_widths: new_columns_widths}
  end

  @doc group: "Pipe API"
  @doc """
  Render the table

  The output is `t:IO.ANSI.ansidata/0` and so it contains atoms representing
  ANSI escape codes. Call `IO.ANSI.format/2` to convert to `t:IO.chardata/0`
  for printing.
  """
  @spec render(t()) :: IO.ANSI.ansidata()
  def render(table) do
    table = fill_in_defaults(table)

    ordered_header = for c <- table.columns, do: {c, table.header[c]}
    {table, header} = table.style.(table, :header, ordered_header)
    {table, rows} = render_rows(table)
    {_table, footer} = table.style.(table, :footer, ordered_header)

    [header, rows, footer]
  end

  defp render_rows(table) do
    # 1. Order the data in each row
    # 2. Group the rows that are horizontally adjacent for multi-column rendering
    # 3. Style the groups
    count = ceil(length(table.data) / table.wrap_across)
    columns = table.columns
    format = table.format
    empty_row = for c <- columns, do: {c, []}

    input_rows =
      table.data
      |> Enum.map(fn row -> for c <- columns, do: {c, format.(c, row[c])} end)
      |> Enum.chunk_every(count, count, Stream.cycle([empty_row]))
      |> Enum.zip_with(&Function.identity/1)

    # Style everything
    {table, output_r} =
      Enum.reduce(input_rows, {table, []}, fn rows, {table, acc} ->
        {table, result} = table.style.(table, :rows_across, rows)
        {table, [result | acc]}
      end)

    {table, Enum.reverse(output_r)}
  end

  @doc group: "Styles/Formatting"
  @doc """
  Simple table styling

  The header row is underlined and data rows are only padded to fit.

  This is the default style, but you can specify it explicitly by passing
  `style: &MyTable.simple_style/3` to `new/1` or `puts/2`.
  """
  @spec simple_style(t(), styling_step(), any()) :: {t(), IO.ANSI.ansidata()}
  def simple_style(table, :header, row) do
    one_header =
      Enum.map(row, fn {c, v} ->
        width = table.column_widths[c]
        [:underline, left_trim_pad(v, width), :reset, "  "]
      end)

    out = [List.duplicate(one_header, table.wrap_across) |> Enum.intersperse(" "), "\n"]
    {table, out}
  end

  def simple_style(table, :rows_across, rows) do
    out = [rows |> Enum.map(&simple_style_row(table, &1)) |> Enum.intersperse(" "), "\n"]
    {table, out}
  end

  def simple_style(table, :footer, _row) do
    # No footer
    {table, []}
  end

  defp simple_style_row(table, row) do
    Enum.map(row, fn {c, v} ->
      width = table.column_widths[c]
      [left_trim_pad(v, width), :reset, "  "]
    end)
  end

  @doc group: "Styles/Formatting"
  @doc """
  Markdown table styling

  To use, pass `style: &MyTable.markdown_style/3` to `new/1` or `puts/2`.
  """
  @spec markdown_style(t(), styling_step(), any()) :: {t(), IO.ANSI.ansidata()}
  def markdown_style(table, :header, row) do
    one_header =
      Enum.map(row, fn {c, v} ->
        width = table.column_widths[c]
        ["| ", left_trim_pad(v, width), :reset, " "]
      end)

    one_separator =
      Enum.map(row, fn {c, _v} ->
        width = table.column_widths[c]
        ["| ", String.duplicate("-", width), " "]
      end)

    out = [
      List.duplicate(one_header, table.wrap_across),
      "|\n",
      List.duplicate(one_separator, table.wrap_across),
      "|\n"
    ]

    {table, out}
  end

  def markdown_style(table, :rows_across, rows) do
    out = [rows |> Enum.map(&markdown_style_row(table, &1)), "|\n"]
    {table, out}
  end

  def markdown_style(table, :footer, _row) do
    # No footer
    {table, []}
  end

  defp markdown_style_row(table, row) do
    Enum.map(row, fn {c, v} ->
      width = table.column_widths[c]
      ["| ", left_trim_pad(v, width), :reset, " "]
    end)
  end

  @doc group: "Styles/Formatting"
  @doc """
  Default formatting for table data

  If the data looks like `t:IO.ANSI.ansidata/0`, it is returned as-is.
  Otherwise, the data is converted to a string. Override this if you'd like to
  apply custom formatting to cell data. For example, you could align floating
  point numbers based on their decimal point or colorize out of range values.
  Formatting is done prior to styling.

  To use, pass `format: &MyTable.default_format/2` to `new/1` or `puts/2`.
  """
  @spec default_format(column_id(), any()) :: IO.ANSI.ansidata()
  def default_format(_id, data) when is_list(data) or is_binary(data), do: data
  def default_format(_id, data) when is_integer(data), do: Integer.to_string(data)
  def default_format(_id, data) when is_float(data), do: Float.to_string(data)
  def default_format(_id, data) when is_map(data), do: inspect(data)
  def default_format(_id, nil), do: ""
  def default_format(_id, data) when is_atom(data), do: inspect(data)
  def default_format(_id, data) when is_tuple(data), do: inspect(data)

  @doc group: "Utility"
  @doc """
  Trim or pad ansidata

  This function is useful for styling output to fit data into a cell.
  """
  @spec left_trim_pad(IO.ANSI.ansidata(), pos_integer()) :: IO.ANSI.ansidata()
  def left_trim_pad(ansidata, len) do
    padding = len - visual_length(ansidata)

    cond do
      padding > 0 -> [ansidata, :binary.copy(" ", padding)]
      padding == 0 -> ansidata
      padding < 0 -> [ansidata, :binary.copy("\b", -padding + 1), "…"]
    end
  end

  @doc group: "Utility"
  @doc """
  Convenience function for simplifying ansidata

  This is useful when debugging or checking output for unit tests. It flattens
  the list, combines strings, and removes redundant ANSI codes.
  """
  @spec simplify(IO.ANSI.ansidata()) :: IO.ANSI.ansidata()
  def simplify(ansidata) do
    ansidata |> simplify([]) |> Enum.reverse() |> merge_ansi(:reset) |> merge_text("")
  end

  defp simplify([], acc), do: acc
  defp simplify([h | t], acc), do: simplify(t, simplify(h, acc))
  defp simplify(b, acc), do: [b | acc]

  defp merge_ansi([last_ansi | t], last_ansi), do: merge_ansi(t, last_ansi)
  defp merge_ansi([h | t], _last_ansi) when is_atom(h), do: [h | merge_ansi(t, h)]
  defp merge_ansi([h | t], last_ansi), do: [h | merge_ansi(t, last_ansi)]
  defp merge_ansi([], _last_ansi), do: []

  defp merge_text([h | t], last) when is_binary(h), do: merge_text(t, last <> h)
  defp merge_text([h | t], "") when is_atom(h), do: [h | merge_text(t, "")]
  defp merge_text([h | t], last) when is_atom(h), do: [last, h | merge_text(t, "")]
  defp merge_text([h | t], last) when is_integer(h), do: merge_text(t, <<last::binary, h::utf8>>)
  defp merge_text([], ""), do: []
  defp merge_text([], last), do: [last]

  @doc group: "Utility"
  @doc """
  Calculate the visual length of an ansidata string

  This function has simplistic logic to account for Unicode characters that
  typically render in the space of two characters when using a fixed width font.
  """
  @spec visual_length(IO.ANSI.ansidata()) :: non_neg_integer()
  def visual_length(ansidata) when is_binary(ansidata) or is_list(ansidata) do
    IO.ANSI.format(ansidata, false)
    |> IO.chardata_to_string()
    |> String.graphemes()
    |> Enum.reduce(0, fn c, acc -> acc + grapheme_width(c) end)
  end

  # Simplistic width calculator for commonly seen Unicode in tables
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp grapheme_width(<<cp::utf8, _::binary>>) do
    cond do
      # Common catch-all for many 1-wide codepoints
      cp < 0x2000 -> 1
      # Watch, hourglass
      cp in 0x231A..0x231B -> 2
      # Angle brackets
      cp in 0x2329..0x232A -> 2
      cp in 0x23E9..0x23EC -> 2
      cp == 0x25B6 -> 2
      cp == 0x25C0 -> 2
      # Misc symbols
      cp in 0x2600..0x27BF -> 2
      cp in 0x2B05..0x2B07 -> 2
      cp in 0x2934..0x2935 -> 2
      cp == 0x1F004 -> 2
      cp == 0x1F0CF -> 2
      # Emoji, pictographs
      cp in 0x1F170..0x1F9FF -> 2
      true -> 1
    end
  end
end
