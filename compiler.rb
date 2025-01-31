require 'json'

module Compiler
  class << self
    def compile(md)
      tks = Lexer.new(md).tokenize
      ast = Parser.new(tks).parse
      CodeGen.new(ast).gen
    end
  end

  class Lexer

    Token = Struct.new(:type, :attrs)

    def initialize(md)
      @md = String.new(md)
    end

    def tokenize
      tks = []

      @md.lstrip!
      while !@md.empty?
        if @md =~ /\A((?:######|#####|####|###|##|#) .+)/
          text = $1
          size = 0
          while text[0] == '#'
            size += 1
            text.slice!(0, text[1] == ' ' ? 2 : 1)
          end
          tks.push Token.new(:header, {size:, text:})
          lslice($1.size)
        elsif @md =~ /\A(\*\*.+?\*\*|__.+?__)/
          tks.push Token.new(:bold, {text: (text = $1).gsub(/[\*_]/, '')})
          lslice(text.size)
        elsif @md =~ /\A(=+|-+) *$/
          size = $1.include?('=') ? 1 : 2
          tks.push Token.new(:header_alt, {size:})
          lslice($1.size)
        elsif @md =~ /\A\n/
          tks.push Token.new(:newl)
          lslice(1)
        elsif @md =~ /\A(.+)/
          tks.push Token.new(:text, {text: $1})
          lslice($1.size)
        else
          raise RuntimeError, "Couldn't match token on '#{@md}'"
        end

        @md.rstrip!
      end
        
      if tks.last && tks.last.type != :endl
        tks.push Token.new(:endl)
      end

      tks
    end

    def lslice(count)
      @md.slice!(0, count)
    end
  end

  class Parser
    
    NodeRoot   = Struct.new(:children)
    NodeHeader = Struct.new(:size, :text)
    NodePara   = Struct.new(:children)
    NodeText   = Struct.new(:text, :bold)

    def initialize(tks)
      @tks = tks
    end

    def parse
      ast = NodeRoot.new(children: [])
      
      while !@tks.empty?
        ast.children << (
          if peek(:header)
            parse_header
          elsif peek(:text) && peek(:newl, 2) && peek(:header_alt, 3)
            parse_header_alt
          elsif peek(:text) || peek(:bold)
            parse_paragraph
          else
            raise RuntimeError, "Unable to parse tokens:\n#{JSON.pretty_generate(@tks)}"
          end
        )
      end

      ast
    end

    private

    def parse_header
      token = consume(:header)
      consume(:endl)
      NodeHeader.new(size: token.attrs[:size], text: token.attrs[:text])
    end

    def parse_header_alt
      text = consume(:text).attrs[:text]
      consume(:newl)
      size = consume(:header_alt).attrs[:size]
      consume(:endl)
      NodeHeader.new(size:, text:)
    end

    def parse_paragraph
      para = NodePara.new(children: [])

      while peek(:text) || peek(:bold)
        para.children << (
          if peek(:text)
            NodeText.new(text: consume(:text).attrs[:text])
          elsif peek(:bold)
            NodeText.new(text: consume(:bold).attrs[:text], bold: true)
          end
        )
      end
      consume(:endl)
      
      para
    end

    def peek(type, depth = 1)
      (token = @tks[depth - 1]) && token.type == type
    end

    def consume(type)
      token = @tks.shift
      if token.nil?
        raise RuntimeError, "Expected to find token type #{type} but did not find a token"
      elsif token.type != type
        raise RuntimeError, "Expected to find token type #{type} but found #{token.type}"
      end
      token
    end
  end

  class CodeGen
    def initialize(ast)
      @ast = ast
    end

    def gen
      html = String.new

      @ast.children.each do |node|
        html << (
          case node
          when Parser::NodeHeader
            gen_header(node)
          when Parser::NodePara
            gen_paragraph(node)
          else
            raise RuntimeError, "Invalid node: #{node}"
          end
        )
      end

      html
    end

    private

    def gen_header(node)
      "<h#{node.size}>#{node.text}</h#{node.size}>"
    end

    def gen_paragraph(node)
      "<p>#{node.children.map { gen_text it }.join('')}</p>"
    end

    def gen_text(node)
      node.bold ? "<em>#{node.text}</em>" : node.text
    end
  end
end