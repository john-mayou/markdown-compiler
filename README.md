# Markdown Compiler

A Markdown-to-HTML compiler written in Ruby. This project demonstrates core concepts of compiler construction, including lexical analysis, parsing, syntax transformation, and code generation.

## How It Works

The compiler follows a classic pipeline:

1. Lexer (Tokenizer): Scans the raw Markdown input and produces a list of tokens.
2. Parser: Processes tokens into an abstract syntax tree (AST) representing the document structure.
3. Code Generator: Converts the AST into the target language (HTML).

## Example

The image below shows the compiler integrated into my personal website to compile Markdown in an IDE-like UI. This code has been copied into that repo (pinned on my profile) as has since been altered to fit the needs of that project.

<img width="1920" src="https://github.com/user-attachments/assets/84c0e223-7553-487c-9275-6167ae847872" />

## Supported Syntax

- Headers (`#`, `##`, etc.)
- Bold / Italic text
- Ordered and Unordered Lists
- Code Blocks
- Inline Code
- Blockquotes
- Horizontal Rules
- Links & Images

A full example of compiled output can be found in `testdata/example.html`.

## Usage

```ruby
Compiler.compile('# Hello world')
# => '<h1>Hello world</h1>'
```

## Testing

```bash
./test.sh
```

_(If needed: `chmod +x test.sh` to make the script executable.)_

## License

MIT
