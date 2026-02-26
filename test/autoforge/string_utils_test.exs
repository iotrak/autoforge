defmodule Autoforge.StringUtilsTest do
  use ExUnit.Case, async: true

  alias Autoforge.StringUtils

  doctest Autoforge.StringUtils

  describe "split_phrases/1" do
    test "splits simple space-separated words" do
      assert StringUtils.split_phrases("hello world") == ["hello", "world"]
      assert StringUtils.split_phrases("one two three") == ["one", "two", "three"]
      assert StringUtils.split_phrases("  leading  trailing  ") == ["leading", "trailing"]
    end

    test "handles double-quoted phrases" do
      assert StringUtils.split_phrases("hello \"big world\"") == ["hello", "big world"]
      assert StringUtils.split_phrases("\"quoted phrase\"") == ["quoted phrase"]
      assert StringUtils.split_phrases("one \"two words\" three") == ["one", "two words", "three"]
    end

    test "handles single-quoted phrases" do
      assert StringUtils.split_phrases("hello 'big world'") == ["hello", "big world"]
      assert StringUtils.split_phrases("'quoted phrase'") == ["quoted phrase"]
      assert StringUtils.split_phrases("one 'two words' three") == ["one", "two words", "three"]
    end

    test "handles quotes in the middle of text" do
      assert StringUtils.split_phrases("hello'big world'") == ["hello", "big world"]
      assert StringUtils.split_phrases("hello\"big world\"") == ["hello", "big world"]
      assert StringUtils.split_phrases("prefix'middle'suffix") == ["prefix", "middle", "suffix"]
    end

    test "handles mixed quotes" do
      assert StringUtils.split_phrases("\"outer 'inner' quotes\"") == ["outer 'inner' quotes"]
      assert StringUtils.split_phrases("'outer \"inner\" quotes'") == ["outer \"inner\" quotes"]
    end

    test "handles empty strings" do
      assert StringUtils.split_phrases("") == []
      assert StringUtils.split_phrases("   ") == []
    end

    test "handles strings with only quotes" do
      assert StringUtils.split_phrases("''") == [""]
      assert StringUtils.split_phrases("\"\"") == [""]
    end

    test "handles unclosed quotes" do
      assert StringUtils.split_phrases("unclosed quote'") == ["unclosed", "quote"]
      assert StringUtils.split_phrases("unclosed \"quote") == ["unclosed", "quote"]
    end

    test "handles multiple consecutive spaces" do
      assert StringUtils.split_phrases("multiple   spaces") == ["multiple", "spaces"]

      assert StringUtils.split_phrases("'quoted  multiple  spaces'") == [
               "quoted  multiple  spaces"
             ]
    end
  end
end
