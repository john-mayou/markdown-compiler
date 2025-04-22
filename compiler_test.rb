require 'minitest/autorun'
require 'fileutils'
require 'open3'

require_relative 'compiler.rb'

UPDATE = ENV['UPDATE'] == 'true'

class Minitest::Test
  make_my_diffs_pretty!
end

module Compiler
  class TestLexer < Minitest::Test
    def tokenize(md)
      Lexer.new(md).tokenize
    end

    def test_tokenize_paragraph
      assert_equal [
        Lexer::Token.new(:text, {text: 'text', bold: false, italic: false}),
        Lexer::Token.new(:newl),
      ], tokenize('text')
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

    def test_parse_paragraph
      assert_equal ast_root(Parser::NodePara.new(children: [Parser::NodeText.new(text: 'text')])),
        parse([
          Lexer::Token.new(:text, {text: 'text', bold: false, italic: false}),
          Lexer::Token.new(:newl),
        ])
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

    def test_gen_paragraph
      assert_equal '<p>text</p>', gen(ast_root(Parser::NodePara.new(children: [Parser::NodeText.new(text: 'text')])))
    end
  end

  class TestGolden < Minitest::Test
    filepaths = Dir.glob('testdata/*.text')
    filepaths.each do |filepath|
      define_method("test_golden_#{File.basename(filepath, '.text')}") do
        html = Compiler.compile(File.read(filepath))
        html, err, status = Open3.capture3('prettier --parser html', stdin_data: html)
        if !status.success?
          raise SystemCallError, err
        end

        html_filepath = "testdata/#{File.basename(filepath, '.text')}.html"
        if !File.exist?(html_filepath)
          FileUtils.touch(html_filepath)
        end 
          
        if UPDATE
          File.write(html_filepath, html)
        end

        assert_equal File.read(html_filepath), html
      end
    end
  end
end