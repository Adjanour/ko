
```ebnf

// TOP LEVEL

program ::=
    ( declaration | TERM )* EOF

declaration ::=
      import_decl
    | struct_decl
    | enum_decl
    | func_decl

import_decl ::=
    "import" path

path ::=
    IDENTIFIER ( "." IDENTIFIER )*



// DIRECTIVES

directive ::=
    "#" IDENTIFIER ( "(" args? ")" )?



// DATA DECLARATIONS

struct_decl ::=
    "struct" IDENTIFIER directive*
    "{"
        field_list?
    "}"

enum_decl ::=
    "enum" IDENTIFIER directive*
    "{"
        variant_list?
    "}"

field_list ::=
    field ( "," field )* ","?

field ::=
    directive* IDENTIFIER ":" type

variant_list ::=
    variant ( "," variant )* ","?

variant ::=
    IDENTIFIER
    ( "(" field_list ")" )?

// TYPES

type ::=
      "!" type
    | "?" type
    | "[" "]" type
    | "*" type
    | "[" "*" "many" "]" type
    | path


// FUNCTIONS

func_decl ::=
    "func"
    IDENTIFIER
    "(" param_list? ")"
    type?
    block

param_list ::=
    param ( "," param )* ","?

param ::=
    "mut"? IDENTIFIER ":" type


// BLOCKS AND STATEMENTS

block ::=
    "{"
        ( statement | TERM )*
    "}"

statement ::=
      let_stmt
    | assignment
    | defer_stmt
    | return_stmt
    | flow_stmt
    | while_stmt
    | expr_stmt

let_stmt ::=
    "let" "mut"?
    IDENTIFIER
    ( ":" type )?
    "="
    expression

assignment ::=
    postfix_expr assign_op expression

assign_op ::=
      "="
    | "+="
    | "-="
    | "*="
    | "/="

defer_stmt ::=
    "defer" expression

return_stmt ::=
    "return" expression?

flow_stmt ::=
      "break"
    | "continue"

expr_stmt ::=
    expression



// CAPTURE AND LOOPS

capture ::=
    "as" IDENTIFIER

while_stmt ::=
    "while"
    expression
    capture?
    block


// IF EXPRESSIONS

if_expr ::=
    "if"
    expression
    capture?
    block
    (
        "else"
        capture?
        (
            if_expr
          | block
        )
    )?


// MATCH EXPRESSIONS

match_expr ::=
    "match"
    expression
    "{"
        (
            match_arm
            ( "," match_arm )*
            ","?
        )?
    "}"

match_arm ::=
    pattern
    ( "if" expression )?
    "=>"
    (
        block
      | expression
    )


// PATTERNS

pattern ::=
      "_"
    | literal
    | IDENTIFIER
    | variant_pattern

variant_pattern ::=
    "." IDENTIFIER
    ( "(" pattern_list? ")" )?

pattern_list ::=
    pattern ( "," pattern )* ","?


// EXPRESSIONS

expression ::=
    recovery_expr

recovery_expr ::=
    pipe_expr
    ( "or" fallback )?

fallback ::=
      return_fallback
    | flow_fallback
    | block
    | pipe_expr

return_fallback ::=
    "return" expression?

flow_fallback ::=
      "break"
    | "continue"

pipe_expr ::=
    binary_expr
    ( "|>" pipe_target )*

pipe_target ::=
    postfix_expr

binary_expr ::=
    unary_expr
    ( binary_op unary_expr )*

binary_op ::=
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
    | "%"

unary_expr ::=
    unary_op* postfix_expr

unary_op ::=
      "!"
    | "-"
    | "try"

postfix_expr ::=
    primary_expr postfix_part*

postfix_part ::=
      "." IDENTIFIER
    | "(" args? ")"
    | "[" expression "]"

primary_expr ::=
      IDENTIFIER
    | literal
    | "(" expression ")"
    | enum_literal
    | struct_literal
    | if_expr
    | match_expr


// LITERALS AND CONSTRUCTION

enum_literal ::=
    "." IDENTIFIER
    ( "(" args? ")" )?

struct_literal ::=
    path
    "{"
        struct_initializer_list?
    "}"

struct_initializer_list ::=
    struct_initializer
    ( "," struct_initializer )*
    ","?

struct_initializer ::=
    IDENTIFIER ":" expression

args ::=
    expression
    ( "," expression )*
    ","?

literal ::=
      INT
    | FLOAT
    | STRING
    | CHAR
    | "true"
    | "false"
```
