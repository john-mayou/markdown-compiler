require 'minitest/autorun'

require_relative 'compiler.rb'

module Compiler
  class TestLexer < Minitest::Test
    def test_tokenize
      assert_equal '', Lexer.new('').tokenize
    end
  end
end