# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.MyTableTest do
  use ExUnit.Case, async: true

  alias Alarmist.MyTable
  import ExUnit.CaptureIO

  doctest MyTable

  defp ansidata_to_string(ansidata, opts \\ [ansi_enabled?: false]) do
    ansidata
    |> IO.ANSI.format(opts[:ansi_enabled?])
    |> IO.chardata_to_string()
    |> String.split("\n")
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.join("\n")
  end

  defp generate_table(rows, columns) do
    for r <- 1..rows do
      for c <- 1..columns, into: %{} do
        {"key_#{c}", "#{r},#{c}"}
      end
    end
  end

  defp removes_trailing_spaces(string) do
    string
    |> String.split("\n")
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.join("\n")
  end

  test "puts/2" do
    data = [%{id: 1, name: "Sherlock"}, %{id: 2, name: "John"}]
    output = capture_io(fn -> MyTable.puts(data, ansi_enabled?: false) end)

    expected = """
    id  name
    1   Sherlock
    2   John
    """

    assert removes_trailing_spaces(output) == expected
  end

  test "table with emojis" do
    header = %{country: "COUNTRY", capital: "CAPITAL", flag: "FLAG", mcd: "McDONALD'S LOCATIONS"}

    data = [
      %{country: "France", capital: "Paris", flag: "🇫🇷", mcd: "1,500+"},
      %{country: "Japan", capital: "Tokyo", flag: "🇯🇵", mcd: "2,900+"},
      %{country: "Brazil", capital: "Brasília", flag: "🇧🇷", mcd: "1,000+"},
      %{country: "Kenya", capital: "Nairobi", flag: "🇰🇪", mcd: "6"},
      %{country: "Canada", capital: "Ottawa", flag: "🇨🇦", mcd: "1,400+"},
      %{country: "Australia", capital: "Canberra", flag: "🇦🇺", mcd: "1,000+"},
      %{country: "Norway", capital: "Oslo", flag: "🇳🇴", mcd: "70+"},
      %{country: "India", capital: "New Delhi", flag: "🇮🇳", mcd: "300+"},
      %{country: "Mexico", capital: "Mexico City", flag: "🇲🇽", mcd: "400+"}
    ]

    expected_output = """
    COUNTRY    CAPITAL      FLAG  McDONALD'S LOCATIONS
    France     Paris        🇫🇷    1,500+
    Japan      Tokyo        🇯🇵    2,900+
    Brazil     Brasília     🇧🇷    1,000+
    Kenya      Nairobi      🇰🇪    6
    Canada     Ottawa       🇨🇦    1,400+
    Australia  Canberra     🇦🇺    1,000+
    Norway     Oslo         🇳🇴    70+
    India      New Delhi    🇮🇳    300+
    Mexico     Mexico City  🇲🇽    400+
    """

    output =
      MyTable.new()
      |> MyTable.set_header(header)
      |> MyTable.set_data(data)
      |> MyTable.set_columns([:country, :capital, :flag, :mcd])
      |> MyTable.auto_size_columns()
      |> MyTable.render()

    assert ansidata_to_string(output) == expected_output
  end

  test "missing columns" do
    header = [name: "NAME", age: "AGE", favorite_food: "FAVORITE FOOD"]

    data = [
      %{name: "Bob", age: "10", favorite_food: "Spaghetti"},
      %{name: "Steve", age: "11"},
      %{name: "Amy", age: "12", favorite_food: "Grilled Cheese"}
    ]

    output =
      MyTable.new()
      |> MyTable.set_header(header)
      |> MyTable.set_data(data)
      |> MyTable.auto_size_columns()
      |> MyTable.render()
      |> MyTable.simplify()

    expected = [
      :underline,
      "NAME ",
      :reset,
      "  ",
      :underline,
      "AGE",
      :reset,
      "  ",
      :underline,
      "FAVORITE FOOD ",
      :reset,
      "  \nBob    10   Spaghetti       \nSteve  11                   \nAmy    12   Grilled Cheese  \n"
    ]

    assert output == expected
  end

  test "list of matching maps with string keys" do
    data = [%{"id" => 1, "name" => "Sherlock"}, %{"id" => 2, "name" => "John"}]

    output =
      MyTable.new()
      |> MyTable.set_data(data)
      |> MyTable.auto_size_columns()
      |> MyTable.render()
      |> ansidata_to_string()

    expected = """
    id  name
    1   Sherlock
    2   John
    """

    assert output == expected
  end

  test "list of matching key-value lists" do
    data = [[{"id", 1}, {"name", "Sherlock"}], [{"id", 2}, {"name", "John"}]]

    output =
      MyTable.new()
      |> MyTable.set_data(data)
      |> MyTable.auto_size_columns()
      |> MyTable.render()
      |> ansidata_to_string()

    expected = """
    id  name
    1   Sherlock
    2   John
    """

    assert output == expected
  end

  test "multi-column" do
    data = generate_table(28, 2)

    output =
      MyTable.new()
      |> MyTable.set_data(data)
      |> MyTable.auto_size_columns()
      |> MyTable.set_wrap_across(3)
      |> MyTable.render()
      |> ansidata_to_string()

    expected = """
    key_1  key_2   key_1  key_2   key_1  key_2
    1,1    1,2     11,1   11,2    21,1   21,2
    2,1    2,2     12,1   12,2    22,1   22,2
    3,1    3,2     13,1   13,2    23,1   23,2
    4,1    4,2     14,1   14,2    24,1   24,2
    5,1    5,2     15,1   15,2    25,1   25,2
    6,1    6,2     16,1   16,2    26,1   26,2
    7,1    7,2     17,1   17,2    27,1   27,2
    8,1    8,2     18,1   18,2    28,1   28,2
    9,1    9,2     19,1   19,2
    10,1   10,2    20,1   20,2
    """

    assert output == expected
  end

  test "expanding columns" do
    data = generate_table(4, 4)

    output =
      MyTable.new()
      |> MyTable.set_data(data)
      |> MyTable.auto_size_columns()
      |> MyTable.expand_column("key_2", 60)
      |> MyTable.render()
      |> ansidata_to_string()

    expected = """
    key_1  key_2                                    key_3  key_4
    1,1    1,2                                      1,3    1,4
    2,1    2,2                                      2,3    2,4
    3,1    3,2                                      3,3    3,4
    4,1    4,2                                      4,3    4,4
    """

    assert output == expected
  end

  test "markdown" do
    data = generate_table(2, 3)

    output =
      MyTable.new(style: &MyTable.markdown_style/3)
      |> MyTable.set_data(data)
      |> MyTable.auto_size_columns()
      |> MyTable.render()
      |> ansidata_to_string()

    expected = """
    | key_1 | key_2 | key_3 |
    | ----- | ----- | ----- |
    | 1,1   | 1,2   | 1,3   |
    | 2,1   | 2,2   | 2,3   |
    """

    assert output == expected
  end

  test "multi-column markdown" do
    data = generate_table(5, 3)

    output =
      MyTable.new(style: &MyTable.markdown_style/3)
      |> MyTable.set_data(data)
      |> MyTable.auto_size_columns()
      |> MyTable.set_wrap_across(2)
      |> MyTable.render()
      |> ansidata_to_string()

    expected = """
    | key_1 | key_2 | key_3 | key_1 | key_2 | key_3 |
    | ----- | ----- | ----- | ----- | ----- | ----- |
    | 1,1   | 1,2   | 1,3   | 4,1   | 4,2   | 4,3   |
    | 2,1   | 2,2   | 2,3   | 5,1   | 5,2   | 5,3   |
    | 3,1   | 3,2   | 3,3   |       |       |       |
    """

    assert output == expected
  end

  test "simplify/1" do
    assert MyTable.simplify("hello") == ["hello"]
    assert MyTable.simplify(["hello", " world"]) == ["hello world"]
    assert MyTable.simplify([:red, "hello", :red, " world", :red]) == [:red, "hello world"]
    assert MyTable.simplify([:reset, "hello"]) == ["hello"]
    assert MyTable.simplify([:red, :red, ~c"hello", :reset]) == [:red, "hello", :reset]
  end

  test "visual_length/1" do
    assert MyTable.visual_length("Hello") == 5
    assert MyTable.visual_length("") == 0
    assert MyTable.visual_length("José") == 4
    assert MyTable.visual_length("🇫🇷") == 2
    assert MyTable.visual_length("😀 👻 🐭") == 8
  end
end
