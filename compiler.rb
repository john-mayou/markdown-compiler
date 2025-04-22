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

    LIST_INDENT_SIZE = 2

    def initialize(md)
      @md = String.new(md)
    end

    def tokenize
      @tks = []

      @md.lstrip!
      while !@md.empty?
        if @md =~ /\A(######|#####|####|###|##|#) / # header
          @tks << Token.new(:header, {size: $1.size})
          @md.slice!(0, $1.size + 1)
          tokenize_line cut_current_line!
          @tks << Token.new(:hr)
          @tks << Token.new(:newl)
        elsif @md =~ /\A```(.*?) *$/ # code block
          lang = $1 || ''
          del_current_line!
          code = String.new
          while ch = @md[0]
            code << ch
            @md.slice!(0, 1)
            if @md =~ /\A``` *$/ # closing code block
              break del_current_line!
            end
          end
          @tks << Token.new(:codeblock, {lang:, code:})
          @tks << Token.new(:newl)
        elsif @md =~ /\A(>(?: >)* ?)/ # block quote
          @tks << Token.new(:blockquote, {indent: $1.count('>')})
          @md.slice!(0, $1.size)
          tokenize_line cut_current_line!
        elsif @md =~ /\A(\*{3,}[\* ]*|-{3,}[- ]*)$/ # hr
          @tks << Token.new(:hr)
          @tks << Token.new(:newl)
          @md.slice!(0, $1.size + 1)
        elsif @md =~ /\A *(([0-9]\.)|(\*|-)) / # list
          i = 0
          loop do
            case @md[i]
            when '*', '-'
              @tks << Token.new(:listi, {indent: (i / LIST_INDENT_SIZE).floor, ordered: false})
              i += 1 # for ' '
              break
            when /(\d)/ # only support one digit for now
              @tks << Token.new(:listi, {indent: (i / LIST_INDENT_SIZE).floor, ordered: true, digit: $1.to_i})
              i += 2 # for '. '
              break
            when ' '
              i += 1
            else
              raise RuntimeError, "Invalid character found: '#{ch}'"
            end
          end
          @md.slice!(0, i + 1)
          tokenize_line cut_current_line!
        elsif @md =~ /\A.+\n(=+|-+) */ # header alt
          curr_line = cut_current_line!
          next_line = cut_current_line!
          @tks << Token.new(:header, {size: next_line.include?('=') ? 1 : 2})
          tokenize_line curr_line
          @tks << Token.new(:hr)
          @tks << Token.new(:newl)
        elsif @md =~ /\A\n/ # new line
          @tks << Token.new(:newl)
          @md.slice!(0, 1)
        else
          tokenize_line cut_current_line!
        end

        @md.rstrip!
      end

      if @tks.last && @tks.last.type != :newl
        @tks << Token.new(:newl)
      end

      @tks
    end

    private

    def tokenize_line(line)
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
        elsif line.start_with?('![') && line =~ /\A!\[(.*)\]\((.*)\)/ # image
          curr_push.call if !curr.empty?
          @tks << Token.new(:image, {alt: $1, src: $2})
          line.slice!(0, $1.size + $2.size + 5) # ![]() = 5
        elsif line.start_with?('[') && line =~ /\A\[(.*)\]\((.*)\)/ # link
          curr_push.call if !curr.empty?
          @tks << Token.new(:link, {text: $1, href: $2})
          line.slice!(0, $1.size + $2.size + 4) # []() = 4
        elsif line.start_with?('`') && line =~ /\A`(.+?)`([a-z]*)/ # code
          curr_push.call if !curr.empty?
          @tks << Token.new(:code, {lang: $2 || '', code: $1})
          line.slice!(0, $1.size + $2.size + 2) # `` = 2
        elsif line.start_with?("\n")
          curr_push.call if !curr.empty?
          @tks << Token.new(:newl)
          line.slice!(0, 1)
        else
          curr << line[0]
          line.slice!(0, 1)
        end
      end
      curr_push.call if !curr.empty?
    end

    def cut_current_line!
      line = String.new
      @md.each_char do |ch|
        line << ch
        break if ch == "\n"
      end
      @md.slice!(0, line.size)
      line.end_with?("\n") ? line : line << "\n" # for consistency
    end

    def del_current_line!
      while ch = @md[0]
        @md.slice!(0, 1)
        break if ch == "\n"
      end
    end
  end

  class Parser

    class StructWithDefaults < Struct
      def initialize(*args, **kwargs)
        super(*args, **kwargs)
        self.class._get_defaults.each { |k, v| self[k] ||= v.call }
      end

      class << self
        def _set_defaults(**defaults) @_defaults = defaults end
        def _get_defaults; @_defaults || {} end
      end
    end

    NodeRoot       = StructWithDefaults.new(:children) { _set_defaults(children: -> { [] }) }
    NodeHeader     = StructWithDefaults.new(:size, :children) { _set_defaults(children: -> { [] }) }
    NodeCode       = Struct.new(:lang, :code)
    NodeCodeBlock  = Struct.new(:lang, :code)
    NodeQuote      = StructWithDefaults.new(:children) { _set_defaults(children: -> { [] }) }
    NodeQuoteItem  = StructWithDefaults.new(:children) { _set_defaults(children: -> { [] }) }
    NodePara       = StructWithDefaults.new(:children) { _set_defaults(children: -> { [] }) }
    NodeText       = StructWithDefaults.new(:text, :bold, :italic) { _set_defaults(bold: -> { false }, italic: -> { false }) }
    NodeHr         = Struct.new
    NodeImage      = Struct.new(:alt, :src)
    NodeLink       = Struct.new(:text, :href)
    NodeList       = StructWithDefaults.new(:ordered, :children) { _set_defaults(children: -> { [] }) }
    NodeListItem   = StructWithDefaults.new(:children) { _set_defaults(children: -> { [] }) }

    def initialize(tks)
      @tks = tks
    end

    def parse
      ast = NodeRoot.new
      
      while !@tks.empty?
        if peek(:header)
          ast.children << parse_header
        elsif peek(:codeblock)
          ast.children << parse_code_block
        elsif peek(:blockquote)
          ast.children << parse_block_quote
        elsif peek(:hr)
          ast.children << parse_hr
        elsif peek(:listi)
          ast.children << parse_list
        elsif peek(:image)
          ast.children << parse_image
        elsif peek_any(:text, :code, :link)
          ast.children << parse_paragraph
        elsif peek(:newl)
          consume(:newl)
        else
          raise RuntimeError, "Unable to parse tokens:\n#{@tks}"
        end
      end

      ast
    end

    private

    def parse_header
      token = consume(:header)
      NodeHeader.new(size: token.attrs[:size], children: parse_inline)
    end

    def parse_code_block
      token = consume(:codeblock)
      consume(:newl)
      NodeCodeBlock.new(lang: token.attrs[:lang], code: token.attrs[:code])
    end

    def parse_block_quote
      root_indent = consume(:blockquote).attrs[:indent]
      root_block = NodeQuote.new(children: [parse_quote_item])

      block_indent_map = {}
      block_indent_map[root_indent] = root_block

      while peek(:blockquote)
        block = consume(:blockquote)
        next consume(:newl) if peek(:newl)

        block_indent = block.attrs[:indent]
        block_node = block_indent_map[block_indent]
        if block_node
          block_node.children << parse_quote_item
        else
          block_node = NodeQuote.new(children: [parse_quote_item])
          block_indent_map[block_indent] = block_node
          block_parent = block_indent_map[block_indent - 1] || root_block
          block_parent.children << block_node
        end
      end

      root_block
    end

    def parse_quote_item
      NodeQuoteItem.new(children: parse_inline_block_quote)
    end
    
    def parse_list
      root = NodeList.new(ordered: consume(:listi).attrs[:ordered])
      root.children << NodeListItem.new(children: parse_inline)
      list_stack = [{node: root, indent: 0}]

      while peek(:listi)
        curr_token = consume(:listi)
        curr_indent = [list_stack[-1][:indent] + 1, curr_token.attrs[:indent]].min # only allow 1 additional level at a time
        last_indent = list_stack[-1][:indent]
        if curr_indent > last_indent
          node = NodeList.new(ordered: curr_token.attrs[:ordered])
          node.children << NodeListItem.new(children: parse_inline)
          list_stack[-1][:node].children.last.children << node
          list_stack << {node:, indent: curr_indent}
        elsif curr_indent < last_indent
          while list_stack[-1][:indent] > curr_indent
            list_stack.pop()
          end
          list_stack[-1][:node].children << NodeListItem.new(children: parse_inline)
        else
          list_stack[-1][:node].children << NodeListItem.new(children: parse_inline)
        end
      end

      root
    end

    def parse_hr
      consume(:hr)
      consume(:newl)
      NodeHr.new
    end

    def parse_image
      image = consume(:image)
      consume(:newl)
      NodeImage.new(alt: image.attrs[:alt], src: image.attrs[:src])
    end

    def parse_paragraph
      NodePara.new(children: parse_inline)
    end

    INLINE_TOKENS = [:text, :code, :link].freeze

    def parse_inline
      nodes = []

      while peek_any(*INLINE_TOKENS) || (peek(:newl) && peek_any(*INLINE_TOKENS, depth: 2))
        if peek(:newl)
          consume(:newl)
          nodes << NodeText.new(text: ' ')
        end

        nodes << parse_inline_single
      end
      consume(:newl)

      nodes
    end

    def parse_inline_block_quote
      nodes = []

      while peek_any(*INLINE_TOKENS) || (peek(:newl) && peek(:blockquote, depth: 2) && peek_any(*INLINE_TOKENS, depth: 3))
        if peek(:newl)
          consume(:newl)
          consume(:blockquote)
          nodes << NodeText.new(text: ' ')
        end

        nodes << parse_inline_single
      end
      consume(:newl)

      nodes
    end

    def parse_inline_single
      if peek(:text)
        consume(:text).attrs => {text:, bold:, italic:}
        NodeText.new(text:, bold:, italic:)
      elsif peek(:code)
        consume(:code).attrs => {lang:, code:}
        NodeCode.new(lang:, code:)
      elsif peek(:link)
        link = consume(:link)
        NodeLink.new(text: link.attrs[:text], href: link.attrs[:href])
      else
        raise "Unexpected next token: \n#{@tks}"
      end
    end

    def peek_any(*types, depth: 1)
      types.each { return true if peek(it, depth:) }
      return false
    end

    def peek(type, depth: 1)
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
          when Parser::NodeCodeBlock
            gen_code_block(node)
          when Parser::NodeQuote
            gen_block_quote(node)
          when Parser::NodeList
            gen_list(node)
          when Parser::NodeHr
            gen_hr(node)
          when Parser::NodeImage
            gen_image(node)
          when Parser::NodeLink
            gen_link(node)
          when Parser::NodeCode
            gen_code(node)
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

    def gen_code_block(node)
      "<pre><code class=\"#{escape_html(node.lang)}\">#{node.code}</code></pre>"
    end

    def gen_block_quote(node)
      html = String.new('<blockquote>')

      node.children.each do |child|
        html << (
          case child
          when Parser::NodeQuote
            gen_block_quote(child)
          when Parser::NodeQuoteItem
            "<p>#{gen_line(child.children)}</p>"
          else
            raise RuntimeError, "Invalid child node: #{child}"
          end
        )
      end

      html << String('</blockquote>')
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

      nodes.each do |node|
        html << (
          case node
          when Parser::NodeLink
            gen_link(node)
          when Parser::NodeCode
            gen_code(node)
          when Parser::NodeText
            gen_text(node)
          else
            raise "Invalid node: #{node}"
          end
        )
      end

      html
    end

    def gen_hr(node)
      '<hr>'
    end

    def gen_image(node)
      "<img alt=\"#{escape_html(node.alt)}\" src=\"#{escape_html(node.src)}\"/>"
    end

    def gen_link(node)
      "<a href=\"#{escape_html(node.href)}\">#{escape_html(node.text)}</a>"
    end

    def gen_code(node)
      "<code class=\"#{escape_html(node.lang)}\">#{node.code}</code>"
    end

    def gen_text(node)
      html = escape_html(node.text)
      node.bold && html.insert(0, '<b>') && html.insert(html.size, '</b>')
      node.italic && html.insert(0, '<i>') && html.insert(html.size, '</i>')
      html
    end

    ESCAPE_HTML_MAP = {
      '<' => '&lt;',
      '>' => '&gt;',
      '&' => '&amp;',
      '"' => '&quot;',
    }.freeze

    def escape_html(str)
      str.gsub(/<|>|&|"/) { ESCAPE_HTML_MAP[it] || raise(RuntimeError, "Invalid char to escape: '#{it}'") }
    end
  end
end