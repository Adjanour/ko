# Kō v0 grammar

This grammar describes the planned parser. The repository currently implements
the tokenizer only; grammar productions are not parser code yet.

The grammar below uses ISO-style Extended Backus-Naur Form (EBNF):

- `=` defines a production;
- `;` terminates a production;
- `,` means concatenation;
- `|` separates alternatives;
- `[ ... ]` denotes an optional element;
- `{ ... }` denotes zero or more repetitions;
- `( ... )` groups grammar elements;
- text in double quotes is a literal token.

`IDENTIFIER`, `NUMBER`, `STRING`, `CHAR`, `TERM`, and `EOF` are tokens
provided by the tokenizer. Keywords and operators written in double quotes
are literal tokens.

```ebnf
(* KŌ v0 GRAMMAR *)

(* TOP LEVEL *)

program = { declaration | TERM }, EOF ;

declaration = import_decl | named_decl ;

import_decl = "import", path ;

path = IDENTIFIER, { ".", IDENTIFIER } ;


(* DIRECTIVES *)

directive = "#", IDENTIFIER, [ "(", [ args ], ")" ] ;


(* DATA DECLARATIONS *)

struct_expr = "struct", { directive }, "{", [ field_list ], "}" ;

enum_expr = "enum", { directive }, "{", [ variant_list ], "}" ;

field_list = field, { ",", field }, [ "," ] ;

field = { directive }, IDENTIFIER, ":", type ;

variant_list = variant, { ",", variant }, [ "," ] ;

variant = IDENTIFIER, [ "(", field_list, ")" ] ;


(* TYPES *)

type =
      "!", type
    | "?", type
    | "[", "]", type
    | "*", type
    | "[", "*", "many", "]", type
    | path ;

(* `many` is contextual here: the tokenizer emits IDENTIFIER, and the
   parser recognizes the lexeme `many` only in this type form. *)


(* NAMED DECLARATIONS AND PROCEDURES *)

procedure = "(", [ param_list ], ")", [ "->", type ], block ;

named_decl =
    IDENTIFIER, "::",
    ( struct_expr | enum_expr | procedure | expression ) ;

param_list = param, { ",", param }, [ "," ] ;

param = IDENTIFIER, ":", type ;


(* BLOCKS AND STATEMENTS *)

block = "{", { statement | TERM }, "}" ;

statement =
      inferred_decl
    | typed_decl
    | assignment
    | defer_stmt
    | return_stmt
    | flow_stmt
    | while_stmt
    | for_stmt
    | expr_stmt ;

inferred_decl = IDENTIFIER, ":=", expression ;

typed_decl = IDENTIFIER, ":", type, "=", expression ;

assignment = postfix_expr, assign_op, expression ;

assign_op = "=" | "+=" | "-=" | "*=" | "/=" ;

defer_stmt = "defer", expression ;

return_stmt = "return", [ expression ] ;

flow_stmt = "break" | "continue" ;

expr_stmt = expression ;


(* CAPTURE AND LOOPS *)

capture = "|", IDENTIFIER, "|" ;

while_stmt = "while", expression, [ capture ], block ;

for_stmt = "for", for_pattern, "in", expression, block ;

for_pattern = IDENTIFIER, { ",", IDENTIFIER } ;


(* IF EXPRESSIONS *)

if_expr =
    "if", expression, [ capture ], block,
    [ "else", ( if_expr | block ) ] ;


(* MATCH EXPRESSIONS *)

match_expr =
    "match", expression, "{",
    [ match_arm, { ",", match_arm }, [ "," ] ],
    "}" ;

match_arm =
    pattern, [ "if", expression ], "=>",
    ( block | expression ) ;


(* PATTERNS *)

pattern = "_" | literal | IDENTIFIER | variant_pattern ;

variant_pattern = ".", IDENTIFIER, [ "(", [ pattern_list ], ")" ] ;

pattern_list = pattern, { ",", pattern }, [ "," ] ;


(* EXPRESSIONS *)

expression = recovery_expr ;

recovery_expr = pipe_expr, [ "or", fallback ] ;

fallback = return_fallback | flow_fallback | block | pipe_expr ;

return_fallback = "return", [ expression ] ;

flow_fallback = "break" | "continue" ;

pipe_expr = range_expr, { "|>", pipe_target } ;

range_expr = binary_expr, [ "..", binary_expr ] ;

pipe_target = postfix_expr ;

binary_expr = unary_expr, { binary_op, unary_expr } ;

binary_op =
      "||"
    | "&&"
    | "=="
    | "!="
    | "<"
    | ">"
    | "<="
    | ">="
    | "+"
    | "-"
    | "*"
    | "/"
    | "%" ;

unary_expr = { unary_op }, postfix_expr ;

unary_op = "!" | "-" | "try" ;

postfix_expr = primary_expr, { postfix_part } ;

postfix_part =
      ".", IDENTIFIER
    | "(", [ args ], ")"
    | "[", expression, "]" ;

primary_expr =
      IDENTIFIER
    | literal
    | "(", expression, ")"
    | enum_literal
    | struct_literal
    | if_expr
    | match_expr ;


(* LITERALS AND CONSTRUCTION *)

enum_literal = ".", IDENTIFIER, [ "(", [ args ], ")" ] ;

struct_literal = path, "{", [ struct_initializer_list ], "}" ;

struct_initializer_list =
    struct_initializer, { ",", struct_initializer }, [ "," ] ;

struct_initializer = IDENTIFIER, ":", expression ;

args = expression, { ",", expression }, [ "," ] ;

literal = NUMBER | STRING | CHAR | "true" | "false" ;
```

The grammar describes expression categories and valid forms. The Pratt parser
uses the following precedence and associativity table for expression parsing.

Higher precedence values bind more tightly. All binary operators are
left-associative. There are currently no right-associative binary operators.

| Binding power | Operators | Fixity | Associativity |
|--------------:|-----------|--------|---------------|
| 10 | `||` | infix | left |
| 20 | `&&` | infix | left |
| 30 | `==`, `!=` | infix | left |
| 40 | `<`, `>`, `<=`, `>=` | infix | left |
| 50 | `+`, `-` | infix | left |
| 60 | `*`, `/`, `%` | infix | left |
| 70 | `!`, `-`, `try` | prefix | right-to-left nesting |
| 80 | `.`, `(...)`, `[...]` | postfix | left-to-right chaining |

For a Pratt implementation using separate left and right binding powers, a
left-associative infix operator at precedence `p` uses `(left = p, right =
p + 1)`. A right-associative infix operator would use `(left = p, right =
p)`. Prefix operators parse their operand at precedence `70`; postfix
operators bind at `80` and therefore attach to the result of a prefix
expression.

Pipeline and recovery are expression layers outside this binary table:

```text
binary expression  ->  range  ->  pipeline  ->  recovery (`or`)
```

Consequently, `a + b |> f or return fallback` groups as:

```text
(a + b |> f) or return fallback
```
