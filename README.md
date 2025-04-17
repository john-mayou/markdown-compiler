# Markdown Compiler

A Markdown to HTML compiler written in Ruby. This project demonstrates core concepts of compiler construction, including parsing, syntax transformation, and code generation.

## Example

The image below shows the compiler being used on my website to compile Markdown in an IDE-like UI. This code has been copied into that repo (pinned on my profile) as has since been altered to fit the needs of that project. 

<img width="1920" src="https://github.com/user-attachments/assets/84c0e223-7553-487c-9275-6167ae847872" />

## Supported Syntax

- Headers
- Bold/Italic
- Ordered/Unordered Lists
- Code Blocks
- Inline Code
- Blockquotes

An example golden test file can be found at `testdata/example.html`.

## Usage

```ruby
Compiler.compile('# Hello world')
=> '<h1>Hello world</h1>'
```
