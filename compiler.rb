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
      @tks = []

      @md.lstrip!
      while !@md.empty?
        if @md =~ /\A((?:######|#####|####|###|##|#) .+)/ # header
          size = 0
          size += 1 while $1[size] == '#'
          @tks << Token.new(:header, {size:})
          @md.slice!(0, size + 1)
          tokenize_remaining_line
          @tks << Token.new(:newl)
          @tks << Token.new(:hr)
        elsif @md =~ /\A(\*{3,}[\* ]*|-{3,}[- ]*)$/ # hr
          @tks << Token.new(:hr)
          @md.slice!(0, $1.size)
        elsif @md =~ /\A *(([0-9]\.)|(\*|-)) / # list
          i = 0
          loop do
            case @md[i]
            when '*', '-'
              @tks << Token.new(:listi, {indent: (i / 2).floor, ordered: false})
              i += 1 # for ' '
              break
            when /(\d)/ # only support one digit for now
              @tks << Token.new(:listi, {indent: (i / 2).floor, ordered: true, digit: $1.to_i})
              i += 2 # for '. '
              break
            when ' '
              i += 1
            else
              raise RuntimeError, "Invalid character found: '#{ch}'"
            end
          end
          @md.slice!(0, i + 1)
          tokenize_remaining_line
        elsif @md =~ /\A\n/
          @tks << Token.new(:newl)
          @md.slice!(0, 1)
        else
          # if there is ---+ or ===+ on the next line, this whole line is a header
          header_line = false
          header_size = nil
          curr_line, next_line = @md.match(/\A(.+)\n((?:=+|-+) *)/)&.captures
          if curr_line && next_line
            header_line = true
            header_size = next_line.include?('=') ? 1 : 2
            @tks << Token.new(:header, {size: header_size})
            @md.slice!(curr_line.size + 1, next_line.size)
          end

          tokenize_remaining_line

          # since we're already cut out next lines chars, we have to handle the hr and newls
          if header_line
            @tks << Token.new(:newl)
            @tks << Token.new(:hr)
            while ch = @md[0]
              @md.slice!(0, 1)
              if ch == "\n"
                @tks << Token.new(:newl)
                break
              end
            end
          end
        end

        @md.rstrip!
      end
        
      if @tks.last && @tks.last.type != :newl
        @tks << Token.new(:newl)
      end

      @tks
    end

    private

    def tokenize_remaining_line
      line = String.new
      @md.each_char { it == "\n" ? break : line << it }
      @md.slice!(0, line.size)
      curr = String.new
      curr_push = lambda {
        @tks << Token.new(:text, {text: curr, bold: false, italic: false})
        curr = String.new
      }
      while !line.empty?
        if (line.start_with?('*') || line.start_with?('_')) && match = line[/\A(\*{3}[^\*]+?\*{3}|_{3}[^_]+?_{3})/, 1] # bold and italic
          curr_push.call if !curr.empty?
          @tks << Token.new(:text, {text: match.gsub(/[\*_]/, ''), bold: true, italic: true})
          line.slice!(0, match.size)
        elsif (line.start_with?('*') || line.start_with?('_')) && match = line[/\A(\*{2}[^\*]+?\*{2}|_{2}[^_]+?_{2})/, 1] # bold
          curr_push.call if !curr.empty?
          @tks << Token.new(:text, {text: match.gsub(/[\*_]/, ''), bold: true, italic: false})
          line.slice!(0, match.size)
        elsif (line.start_with?('*') || line.start_with?('_')) && match = line[/\A(\*[^\*]+?\*|_[^_]+?_)/, 1] # italic
          curr_push.call if !curr.empty?
          @tks << Token.new(:text, {text: match.gsub(/[\*_]/, ''), bold: false, italic: true})
          line.slice!(0, match.size)
        elsif line.start_with?('[') && line =~ /\A(?:\[(.+?)\]\((.*?)\))/ # link
          curr_push.call if !curr.empty?
          @tks << Token.new(:link, {text: $1, href: $2})
          line.slice!(0, $1.size + $2.size + 4) # []() = 4
        else
          curr << line[0]
          line.slice!(0, 1)
        end
      end
      curr_push.call if !curr.empty?
    end
  end

  class Parser
    
    NodeRoot = Struct.new(:children) do
      def initialize(**kwargs)
        super(**kwargs)
        self.children ||= []
      end
    end

    NodeHeader = Struct.new(:size, :children) do
      def initialize(**kwargs)
        super(**kwargs)
        self.children ||= []
      end
    end

    NodePara = Struct.new(:children) do
      def initialize(**kwargs)
        super(**kwargs)
        self.children ||= []
      end
    end

    NodeText = Struct.new(:text, :bold, :italic) do
      def initialize(**kwargs)
        super(**kwargs)
        self.bold ||= false
        self.italic ||= false
      end
    end

    NodeHr = Struct.new

    NodeLink = Struct.new(:text, :href)

    NodeList = Struct.new(:ordered, :children) do
      def initialize(**kwargs)
        super(**kwargs)
        self.children ||= []
      end
    end

    NodeListItem = Struct.new(:children) do
      def initialize(**kwargs)
        super(**kwargs)
        self.children ||= []
      end
    end

    def initialize(tks)
      @tks = tks
    end

    def parse
      ast = NodeRoot.new
      
      while !@tks.empty?
        if peek(:header)
          ast.children << parse_header
        elsif peek(:hr)
          ast.children << parse_hr
        elsif peek(:listi)
          ast.children << parse_list
        elsif peek(:link)
          ast.children << parse_link
        elsif peek(:text)
          ast.children << parse_paragraph
        else
          raise RuntimeError, "Unable to parse tokens:\n#{JSON.pretty_generate(@tks)}"
        end
      end

      ast
    end

    private

    def parse_header
      token = consume(:header)
      NodeHeader.new(size: token.attrs[:size], children: parse_remaining_line)
    end
    
    def parse_list(list_indent_map = {}, last_indent = 0)
      while peek(:listi)
        list_token = consume(:listi)
        list_indent = [last_indent + 1, list_token.attrs[:indent]].min # only allow 1 additional level at a time
        list_node = list_indent_map[list_indent]
        if !list_node
          list_node = NodeList.new(ordered: list_token.attrs[:ordered])
          list_indent_map[list_indent] = list_node
          if list_indent != 0
            list_indent_map[list_indent - 1].children.last.children << list_node
          end
        end
        list_node.children << NodeListItem.new(children: parse_remaining_line)
        parse_list(list_indent_map, list_indent)
      end

      list_indent_map[0]
    end

    def parse_hr
      consume(:hr)
      consume(:newl)
      NodeHr.new
    end

    def parse_link
      link = consume(:link)
      consume(:newl)
      NodeLink.new(text: link.attrs[:text], href: link.attrs[:href])
    end

    def parse_paragraph
      NodePara.new(children: parse_remaining_line)
    end

    def parse_remaining_line
      nodes = []

      while peek_any(:text, :link)
        nodes << (
          if peek(:text)
            consume(:text).attrs => {text:, bold:, italic:}
            NodeText.new(text:, bold:, italic:)
          elsif peek(:link)
            parse_link
          else
            raise "Unexpected next token: \n#{JSON.pretty_generate(@tks)}"
          end
        )
      end
      consume(:newl)

      nodes
    end

    def peek_any(*types)
      types.each { return true if peek it }
      return false
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
          when Parser::NodeList
            gen_list(node)
          when Parser::NodeHr
            gen_hr(node)
          when Parser::NodeLink
            gen_link(node)
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
      "<h#{node.size}>#{gen_line(node.children)}</h#{node.size}>"
    end

    def gen_list(node)
      html = String.new(node.ordered ? String.new('<ol>') : String.new('<ul>'))
      node.children.each { html << gen_list_item(it) }
      html << (node.ordered ? String.new('</ol>') : String.new('</ul>'))
    end

    def gen_list_item(node)
      html = String.new('<li>')
      node.children.each do |child|
        html << (child.is_a?(Parser::NodeList) ? gen_list(child) : gen_line([child]))
      end
      html << String.new('</li>')
    end

    def gen_paragraph(node)
      "<p>#{gen_line(node.children)}</p>"
    end

    def gen_line(nodes)
      html = String.new

      nodes.each do |child|
        html << (
          case child
          when Parser::NodeText
            gen_text(child)
          when Parser::NodeLink
            gen_link(child)
          else
            raise "Invalid node: #{child}"
          end
        )
      end

      html
    end

    def gen_hr(node)
      '<hr>'
    end

    def gen_link(node)
      "<a href=\"#{node.href}\">#{node.text}</a>"
    end

    def gen_text(node)
      html = node.text
      node.bold && html.insert(0, '<b>') && html.insert(html.size, '</b>')
      node.italic && html.insert(0, '<i>') && html.insert(html.size, '</i>')
      html
    end
  end
end