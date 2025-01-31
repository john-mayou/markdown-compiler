require 'minitest/autorun'

require_relative 'compiler.rb'

module Compiler
  class TestCompile < Minitest::Test
    [
      {md: 'text', expected: '<p>text</p>'},
      {md: 'text #', expected: '<p>text #</p>'},
    ].each do |tc, i|
      define_method("test_compile_text_#{i}") do
        assert_equal tc[:expected], Compiler.compile(tc[:md])
      end
    end

    [
      {md: '# text', expected: '<h1>text</h1>'},
      {md: '## text', expected: '<h2>text</h2>'},
      {md: '### text', expected: '<h3>text</h3>'},
      {md: '#### text', expected: '<h4>text</h4>'},
      {md: '##### text', expected: '<h5>text</h5>'},
      {md: '###### text', expected: '<h6>text</h6>'},
    ].each_with_index do |tc, i|
      define_method("test_compile_header_#{i}") do
        assert_equal tc[:expected], Compiler.compile(tc[:md])
      end
    end

    [
      {md: "text\n====", expected: '<h1>text</h1>'},
      {md: "text\n----", expected: '<h2>text</h2>'},
    ].each_with_index do |tc, i|
      define_method("test_compile_header_alt_#{i}") do
        assert_equal tc[:expected], Compiler.compile(tc[:md])
      end
    end
  end

  class TestLexer < Minitest::Test
    def tokenize(md)
      Lexer.new(md).tokenize
    end

    def test_tokenize_blank
      assert_equal [], tokenize('')
    end

    def test_tokenize_text
      assert_equal [Lexer::Token.new(:text, {text: 'text'})], tokenize('text')
    end

    def test_tokenize_header
      assert_equal [Lexer::Token.new(:header, {size: 1, text: 'text'})], tokenize('# text')
    end
  end

  class TestParser < Minitest::Test
    def parse(tks)
      Parser.new(tks).parse
    end

    def ast_root(*children)
      Parser::NodeRoot.new(children:)
    end

    def test_parse_blank
      assert_equal ast_root, parse([])
    end

    def test_parse_text
      assert_equal ast_root(Parser::NodeText.new(text: 'text')),
        parse([Lexer::Token.new(:text, {text: 'text'})])
    end

    def test_parse_header
      assert_equal ast_root(Parser::NodeHeader.new(size: 1, text: 'text')),
        parse([Lexer::Token.new(:header, {size: 1, text: 'text'})])
    end
  end

  class TestCodeGen < Minitest::Test
    def gen(ast)
      CodeGen.new(ast).gen
    end

    def ast_root(*children)
      Parser::NodeRoot.new(children:)
    end

    def test_gen_blank
      assert_equal '', gen(ast_root)
    end

    def test_gen_text
      assert_equal '<p>text</p>', gen(ast_root(Parser::NodeText.new(text: 'text')))
    end

    def test_gen_header
      assert_equal '<h1>text</h1>', gen(ast_root(Parser::NodeHeader.new(size: 1, text: 'text')))
    end
  end
end