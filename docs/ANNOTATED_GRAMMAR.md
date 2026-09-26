
# Kō v0 Annotated Grammar


## Reading the notation

Before the language itself, remember what the EBNF operators mean:

```ebnf
A ::= B
```

means:

> A is defined as B.

```ebnf
A | B
```

means:

> either A or B.

```ebnf
X?
```

means:

> zero or one X.

```ebnf
X*
```

means:

> zero or more X.

```ebnf
X+
```

means:

> one or more X.

Parentheses group grammar expressions:

```ebnf
( "," expression )*
```

means:

> zero or more occurrences of comma followed by an expression.

Quoted values such as:

```ebnf
"func"
"{"
"=>"
```

are actual tokens appearing in source code.

Names such as:

```ebnf
IDENTIFIER
INT
STRING
TERM
EOF
```

are tokens produced by the lexer.

---

# 1. Program structure

```ebnf
// A source file is simply a sequence of declarations and terminators.
//
// TERM appears here because blank lines / inserted statement terminators
// may occur between top-level declarations.

program ::=
    ( declaration | TERM )* EOF


// v0 permits four kinds of top-level declaration.

declaration ::=
      import_decl
    | struct_decl
    | enum_decl
    | func_decl
```

Your original version was:

```ebnf
program ::= declaration* EOF
```

That was completely reasonable initially.

The reason it changes is the introduction of newline termination. Once the lexer can emit:

```text
TERM
```

between declarations, the parser must be willing to encounter them.

---

# 2. Imports and paths

```ebnf
import_decl ::=
    "import" path


// A path represents a qualified name.
//
// Examples:
//
//     io
//     std.io
//     std.mem.Allocator

path ::=
    IDENTIFIER ( "." IDENTIFIER )*
```

Your original rule:

```ebnf
"import" IDENTIFIER ( "." IDENTIFIER )*
```

worked.

The improvement is simply factoring the path out because paths now occur elsewhere:

```ko
import std.io
```

```ko
mem.Allocator
```

Instead of teaching the grammar what a qualified name looks like multiple times, we define it once.

---

# 3. Directives

```ebnf
// Directives attach metadata to declarations or fields.
//
// Examples:
//
//     #repr(C)
//
//     #align(8)
//
//     #something(foo, bar)

directive ::=
    "#" IDENTIFIER ( "(" args? ")" )?
```

Your original rule was:

```ebnf
directive ::= "#" IDENTIFIER ( "(" expression ")" )?
```

That only allowed:

```ko
#foo(x)
```

but not:

```ko
#foo(x, y)
```

Since we already need an argument-list grammar for function calls, we reuse it.

This is an important grammar-design principle:

> If two syntactic constructs genuinely have the same shape, try to describe that shape once.

---

# 4. Structs

```ebnf
struct_decl ::=
    "struct" IDENTIFIER directive*
    "{"
        field_list?
    "}"


field_list ::=
    field ( "," field )* ","?


// Directives are permitted on individual fields as well.

field ::=
    directive* IDENTIFIER ":" type
```

Example:

```ko
struct Header #repr(C) {
    version: u32,
    length: u64,
}
```

This:

```ebnf
field_list ::= field ( "," field )* ","?
```

is worth recognizing as a common grammar pattern.

It says:

1. require one field,
2. then allow as many `, field` pairs as necessary,
3. then permit one final trailing comma.

Thus all of these work:

```ko
struct A {
    x: u64
}
```

```ko
struct A {
    x: u64,
}
```

```ko
struct A {
    x: u64,
    y: u64,
}
```

---

# 5. Enums

```ebnf
enum_decl ::=
    "enum" IDENTIFIER directive*
    "{"
        variant_list?
    "}"


variant_list ::=
    variant ( "," variant )* ","?


variant ::=
    IDENTIFIER
    ( "(" field_list ")" )?
```

Examples:

```ko
enum State {
    Ready,
    Failed,
}
```

and:

```ko
enum Row {
    Valid(id: u64, amount: f64),
    Incomplete(reason: []u8),
    Corrupt,
}
```

Notice something useful here:

```ebnf
variant ::= IDENTIFIER ( "(" field_list ")" )?
```

means the grammar doesn't need separate rules for:

```ko
Corrupt
```

and:

```ko
Valid(id: u64)
```

The payload is simply optional.

---

# 6. Types

This is one of the biggest changes from your original grammar.

```ebnf
// Types are recursive.
//
// That recursion is what makes constructions such as:
//
//     [][]u8
//     ?[]u8
//     !?[]u8
//
// possible.

type ::=
      "!" type
    | "?" type
    | "[" "]" type
    | "*" type
    | "[" "*" "many" "]" type
    | path
```

Read this carefully.

Suppose we encounter:

```ko
[][]u8
```

The parser sees:

```text
[]
```

and applies:

```ebnf
"[" "]" type
```

But that `type` can itself again be:

```ebnf
"[" "]" type
```

Eventually it reaches:

```text
u8
```

which satisfies:

```ebnf
path
```

So structurally:

```text
slice
  slice
    u8
```

That is what **recursive grammar** means in practice.

---

## Type examples

```ko
u64
```

```text
path
```

---

```ko
[]u8
```

```text
slice
└── u8
```

---

```ko
[][]u8
```

```text
slice
└── slice
    └── u8
```

---

```ko
?[]u8
```

```text
optional
└── slice
    └── u8
```

---

```ko
!?[]u8
```

```text
error
└── optional
    └── slice
        └── u8
```

---

```ko
*Stats
```

single-item pointer.

---

```ko
[*many]u8
```

many-item pointer.

The grammar only recognizes these forms.

Questions such as:

> Can `*T` be incremented?

or:

> Can `[*many]T` implicitly become `[]T`?

are **not grammar questions**.

Those belong to semantic/type checking.

---

# 7. Functions

```ebnf
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
```

Examples:

```ko
func run() {
}
```

No explicit return type means `void`.

```ko
func parse(line: []u8) Row {
}
```

```ko
func read() !?[]u8 {
}
```

```ko
func tally(row: Row, mut stats: Stats) {
}
```

---

## Why `!` disappeared from `func_decl`

Your original grammar had:

```ebnf
func_decl ::= "func" IDENTIFIER param_list "!"? type block
```

That made `!` a special property of functions.

But after making types recursive:

```ebnf
type ::= "!" type | ...
```

we no longer need that special case.

This:

```ko
func read() ![]u8
```

is simply:

```text
function returning:

    ![]u8
```

And this:

```ko
func read() !?[]u8
```

also works naturally.

This is a good example of grammar becoming **smaller by finding the right abstraction**.

---

# 8. Blocks

```ebnf
block ::=
    "{"
        ( statement | TERM )*
    "}"
```

Your original version:

```ebnf
block ::= "{" statement* "}"
```

assumed statements appeared immediately beside each other.

Now consider:

```ko
{
    let x = 10

    let y = 20
}
```

The lexer may produce approximately:

```text
{
LET IDENT = INT TERM
TERM
LET IDENT = INT TERM
}
```

So the block grammar must tolerate `TERM` tokens.

---

# 9. Statements

```ebnf
statement ::=
      let_stmt
    | assignment
    | defer_stmt
    | return_stmt
    | flow_stmt
    | while_stmt
    | expr_stmt
```

Notice what disappeared:

```text
if_stmt
match_stmt
```

That is deliberate.

`if` and `match` are now **expressions**.

Therefore:

```ko
let x = if ready {
    10
} else {
    20
}
```

can eventually be legal.

Likewise:

```ko
let result = match value {
    .Some(x) => x,
    .None    => 0,
}
```

The parser does not need separate statement versions of these constructs.

---

# 10. Local bindings

```ebnf
let_stmt ::=
    "let" "mut"?
    IDENTIFIER
    ( ":" type )?
    "="
    expression
```

Examples:

```ko
let x = 10
```

```ko
let x: u64 = 10
```

```ko
let mut x = 10
```

```ko
let mut x: u64 = 10
```

This grammar also encodes one deliberate Kō property:

> There is no uninitialized `let`.

There is no production for:

```ko
let x: u64
```

because `=` and an expression are mandatory.

That is an example of a safety property partially enforced by syntax itself.

---

# 11. Assignment

```ebnf
assignment ::=
    postfix_expr assign_op expression


assign_op ::=
      "="
    | "+="
    | "-="
    | "*="
    | "/="
```

Examples:

```ko
x = 10
```

```ko
stats.valid += 1
```

```ko
items[i] = value
```

But there is an implementation subtlety here.

You probably **should not implement this by asking the parser upfront**:

> Is the next thing an assignment or an expression?

Because both:

```ko
stats.valid
```

and:

```ko
stats.valid += 1
```

begin identically.

Instead, parse the left-hand expression first.

If the next token is an assignment operator:

```text
=
+=
-=
*=
/=
```

then treat it as assignment.

Later semantic analysis decides whether the left side is actually assignable.

For example:

```ko
foo() = 10
```

may be syntactically parseable but semantically invalid.

This separation is important:

> Parsing asks, “What shape does this have?”

> Semantic analysis asks, “Does this shape make sense?”

---

# 12. Defer

For now:

```ebnf
defer_stmt ::=
    "defer" expression
```

Example:

```ko
defer file.close()
```

I would keep this narrower than:

```ebnf
"defer" statement
```

for the initial compiler.

Otherwise the grammar permits strange things like:

```ko
defer return x
```

or:

```ko
defer break
```

If Kō later wants:

```ko
defer {
    cleanup_a()
    cleanup_b()
}
```

we can deliberately extend this to:

```ebnf
defer_stmt ::= "defer" ( expression | block )
```

rather than accidentally allowing every statement.

---

# 13. Return and loop flow

```ebnf
return_stmt ::=
    "return" expression?


flow_stmt ::=
      "break"
    | "continue"
```

Examples:

```ko
return
```

```ko
return value
```

```ko
break
```

```ko
continue
```

Remember that the lexer handles the newline distinction.

Thus:

```ko
return
value
```

becomes something approximately like:

```text
RETURN TERM
IDENTIFIER TERM
```

not:

```ko
return value
```

This is one reason the lexer and parser contracts cannot be designed independently.

---

# 14. Captures

```ebnf
capture ::=
    "as" IDENTIFIER
```

Example:

```ko
while reader.next() as item {
}
```

The grammar only tells us:

> an `as name` capture may appear here.

What that capture *means* depends upon the expression's type.

That meaning belongs later in semantic analysis.

---

# 15. While

```ebnf
while_stmt ::=
    "while"
    expression
    capture?
    block
```

Examples:

```ko
while running {
    work()
}
```

and:

```ko
while reader.next() as line {
    process(line)
}
```

and eventually:

```ko
while try reader.read_line() as line {
    process(line)
}
```

Notice the composition:

```text
while
    try
        read_line()
    as line
{
}
```

There isn't a special grammar rule for `while try`.

`try` is simply part of the expression.

Good grammars tend to gain expressive power through composition like this.

---

# 16. If expressions

```ebnf
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
```

Basic:

```ko
if ready {
    run()
}
```

With else:

```ko
if ready {
    run()
} else {
    wait()
}
```

Else-if:

```ko
if x < 0 {
    negative()
} else if x == 0 {
    zero()
} else {
    positive()
}
```

Notice that we don't need a special `"else if"` token.

The grammar says:

```text
else

followed by either:

    another if expression

or:

    a block
```

So `else if` emerges naturally.

---

# 17. Match expressions

```ebnf
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
```

Simple:

```ko
match state {
    .Ready  => run(),
    .Failed => stop(),
}
```

Block body:

```ko
match state {
    .Ready => {
        prepare()
        run()
    },

    .Failed => stop(),
}
```

Guard:

```ko
match row {
    .Valid(id, amount) if amount > 1000 => review(id),
    .Valid(id, _)                        => accept(id),
    .Corrupt                             => reject(),
}
```

Whether all variants have been handled is **not** a parser problem.

The parser merely records the arms.

The type checker / exhaustiveness checker later determines whether the match is complete.

---

# 18. Patterns

```ebnf
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
```

This is significantly stronger than your original:

```ebnf
pattern ::= "."? IDENTIFIER ...
```

That earlier grammar made:

```ko
Corrupt
```

ambiguous.

Was it:

> bind whatever value exists here to a variable named `Corrupt`

or:

> match the enum variant `Corrupt`?

Now the syntax answers that immediately.

Binding:

```ko
x
```

Variant:

```ko
.Corrupt
```

Binding fields:

```ko
.Valid(id, amount)
```

Ignore something:

```ko
.Valid(id, _)
```

Nested patterns become possible because the payload contains **patterns**, not merely identifiers:

```ko
.Outer(.Inner(x))
```

That is why:

```ebnf
pattern_list ::= pattern ...
```

is preferable to your original:

```ebnf
IDENTIFIER ( "," IDENTIFIER )*
```

---

# 19. Expressions: the important conceptual change

Your original grammar said:

```ebnf
expression ::= prefix_op? primary_expr
               ( infix_op expression )*
```

This was a very good first approximation.

But it has a fundamental problem.

Consider:

```ko
a - b - c
```

That recursive structure tends toward:

```text
a - (b - c)
```

while normal subtraction means:

```text
(a - b) - c
```

And:

```ko
a + b * c
```

needs `*` to bind more tightly than `+`.

Trying to encode all of that directly into one EBNF production becomes unpleasant.

So Kō uses a **Pratt parser** for expression precedence.

The grammar therefore describes expression *categories*, while a precedence table controls their binding.

---

# 20. Expression layers

Conceptually:

```ebnf
expression ::=
    recovery_expr


recovery_expr ::=
    pipe_expr
    ( "or" fallback )?


pipe_expr ::=
    binary_expr
    ( "|>" pipe_target )*


// `binary_expr` is handled by the Pratt engine.
// Do NOT recursively implement this exact production literally.

binary_expr ::=
    unary_expr
    ( binary_op unary_expr )*


unary_expr ::=
    unary_op* postfix_expr


postfix_expr ::=
    primary_expr postfix_part*


postfix_part ::=
      "." IDENTIFIER
    | "(" args? ")"
    | "[" expression "]"
```

Think of these as progressively building an expression outward.

---

# 21. Primary expressions

A primary expression is the smallest self-contained expression.

```ebnf
primary_expr ::=
      IDENTIFIER
    | literal
    | "(" expression ")"
    | enum_literal
    | struct_literal
    | if_expr
    | match_expr
```

Examples:

```ko
x
```

```ko
42
```

```ko
"hello"
```

```ko
(x + y)
```

```ko
.Valid(10)
```

```ko
if condition { a } else { b }
```

```ko
match value { ... }
```

You can think of a primary as:

> something that can stand on its own before operators start attaching to it.

---

# 22. Postfix expressions

```ebnf
postfix_expr ::=
    primary_expr postfix_part*


postfix_part ::=
      "." IDENTIFIER
    | "(" args? ")"
    | "[" expression "]"
```

This tiny rule solves several problems your original grammar could not handle.

Start with:

```ko
parts
```

Then attach:

```text
.len
```

giving:

```ko
parts.len
```

Start with:

```ko
parts
```

attach:

```text
[0]
```

giving:

```ko
parts[0]
```

Start with:

```ko
foo
```

attach:

```text
()
```

then:

```text
.bar
```

then:

```text
(10)
```

then:

```text
[0]
```

and you get:

```ko
foo().bar(10)[0]
```

All from:

```ebnf
primary_expr postfix_part*
```

This is an extremely useful parser pattern.

---

# 23. Function arguments

```ebnf
args ::=
    expression ( "," expression )* ","?
```

Examples:

```ko
foo(x)
```

```ko
foo(x, y)
```

```ko
foo(
    x,
    y,
)
```

The call itself comes from the postfix grammar:

```ebnf
"(" args? ")"
```

So:

```ko
foo()
```

contains no args.

---

# 24. Enum literals

```ebnf
enum_literal ::=
    "." IDENTIFIER
    ( "(" args? ")" )?
```

Examples:

```ko
.Corrupt
```

```ko
.Valid(id, amount)
```

Notice the symmetry:

Pattern:

```ko
.Valid(id, amount)
```

Expression:

```ko
.Valid(id, amount)
```

They look the same in source, but occur in different parser contexts.

That is perfectly okay.

The parser already knows whether it is currently parsing a:

```text
pattern
```

or an:

```text
expression
```

---

# 25. Struct literals

```ebnf
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
```

Example:

```ko
Stats {
    valid: 0,
    review: 0,
    corrupt: 0,
    total: 0.0,
}
```

There is an intentional parser restriction here.

This:

```ko
if x == Point { x: 1 } {
}
```

is potentially difficult to distinguish visually and syntactically from the block beginning after an `if`.

For v0, an unparenthesized struct literal is therefore forbidden directly in condition position.

Write:

```ko
if (x == Point { x: 1 }) {
}
```

The EBNF does not need to encode every contextual restriction.

Your parser can carry a context flag such as:

```text
allow_struct_literal
```

while parsing certain expressions.

This is similar to an important general lesson:

> Not every syntactic restriction needs to make the formal grammar grotesque.

Some are cleaner as parser-context rules.

---

# 26. Literals

```ebnf
literal ::=
      INT
    | FLOAT
    | STRING
    | CHAR
    | "true"
    | "false"
```

The lexer determines whether source text such as:

```text
123
```

is an `INT`.

The parser should not care whether it was:

```ko
123
0xff
0b1010
1_000
```

Those are all lexical representations of the same token class.

---

# 27. Unary expressions

```ebnf
unary_expr ::=
    unary_op* postfix_expr


unary_op ::=
      "!"
    | "-"
    | "try"
```

Examples:

```ko
!ready
```

```ko
-value
```

```ko
try read()
```

```ko
!-value
```

The parser can conceptually build:

```text
Not(
    Negate(
        value
    )
)
```

There is currently **no pointer dereference or address-of operator here**.

That is deliberate.

Although the type grammar knows:

```ko
*T
```

and:

```ko
[*many]T
```

we have not yet deliberately specified the source syntax for operations such as:

```text
take address
dereference
pointer arithmetic
```

Do not invent `&x` or `*p` in the parser merely because C, Rust, or Zig use them.

That deserves its own language decision.

---

# 28. Binary operators

```ebnf
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
```

But again:

> Do not implement binary parsing by literally following this EBNF recursively.

Use Pratt binding powers.

---

# 29. Pratt precedence

From lowest to highest:

```text
1    ||
2    &&
3    == !=
4    < > <= >=
5    + -
6    * / %
```

Unary:

```text
! - try
```

binds tighter than binary operators.

Postfix:

```text
.x
(...)
[...]
```

binds tighter still.

So:

```ko
try foo().items[i] * 2 + 1
```

groups approximately as:

```text
(
    (
        try (
            foo()
                .items
                [i]
        )
        * 2
    )
    + 1
)
```

---

# 30. Pipeline expressions

```ebnf
pipe_expr ::=
    binary_expr
    ( "|>" pipe_target )*


pipe_target ::=
    postfix_expr
```

Examples:

```ko
line |> parse_row
```

means conceptually:

```ko
parse_row(line)
```

and:

```ko
line |> parse_row |> route
```

means:

```ko
route(parse_row(line))
```

A target may itself contain call arguments:

```ko
value |> process(config)
```

which becomes conceptually:

```ko
process(value, config)
```

The pipeline sits below ordinary arithmetic and boolean operators in precedence.

So:

```ko
x + 1 |> f
```

means:

```ko
f(x + 1)
```

not:

```ko
x + f(1)
```

---

# 31. Local error recovery

```ebnf
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
```

Example:

```ko
let id =
    u64.parse(text)
    or return .Incomplete("bad id")
```

Why don't we write:

```ebnf
fallback ::= expression
```

and leave it there?

Because `expression` itself contains:

```text
... or fallback
```

That makes the recursive relationship less constrained and makes implementation harder to reason about.

Instead, the fallback expression drops back to `pipe_expr`.

That gives `or` a clear low precedence.

For example:

```ko
a + b or fallback
```

means:

```text
(a + b) or fallback
```

---

# 32. Expression statements

Finally:

```ebnf
expr_stmt ::=
    expression
```

That permits:

```ko
foo()
```

```ko
line |> process
```

or other expressions to appear for their effects.

Semantic analysis may later reject expressions that make no sense as discarded values if Kō chooses to enforce such a rule.

---

# 33. Complete grammar

Once you understand the pieces above, the complete grammar becomes much less intimidating:

```ebnf
// ============================================================
// KŌ v0 GRAMMAR
// ============================================================


// ------------------------------------------------------------
// TOP LEVEL
// ------------------------------------------------------------

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


// ------------------------------------------------------------
// DIRECTIVES
// ------------------------------------------------------------

directive ::=
    "#" IDENTIFIER ( "(" args? ")" )?


// ------------------------------------------------------------
// DATA
// ------------------------------------------------------------

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


// ------------------------------------------------------------
// TYPES
// ------------------------------------------------------------

// Recursive by design.
//
// !?[]u8 becomes:
//
// error(optional(slice(u8)))

type ::=
      "!" type
    | "?" type
    | "[" "]" type
    | "*" type
    | "[" "*" "many" "]" type
    | path


// ------------------------------------------------------------
// FUNCTIONS
// ------------------------------------------------------------

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


// ------------------------------------------------------------
// BLOCKS
// ------------------------------------------------------------

block ::=
    "{"
        ( statement | TERM )*
    "}"


// ------------------------------------------------------------
// STATEMENTS
// ------------------------------------------------------------

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

// Implementation note:
// Parse the candidate lhs first, then recognize an assignment operator.
// Semantic analysis later verifies that lhs is actually assignable.

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


// ------------------------------------------------------------
// CAPTURE + LOOPS
// ------------------------------------------------------------

capture ::=
    "as" IDENTIFIER

while_stmt ::=
    "while"
    expression
    capture?
    block


// ------------------------------------------------------------
// IF EXPRESSIONS
// ------------------------------------------------------------

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


// ------------------------------------------------------------
// MATCH EXPRESSIONS
// ------------------------------------------------------------

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


// ------------------------------------------------------------
// PATTERNS
// ------------------------------------------------------------

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


// ------------------------------------------------------------
// EXPRESSIONS
//
// These productions describe the expression layers.
// Binary precedence itself is implemented by the Pratt parser.
// ------------------------------------------------------------

expression ::=
    recovery_expr


// `or` deliberately sits outside the normal binary operators.
// Boolean OR is `||`.

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


// Pipelines bind more weakly than ordinary binary operators.
//
// x + 1 |> f
//
// means:
//
// f(x + 1)

pipe_expr ::=
    binary_expr
    ( "|>" pipe_target )*

pipe_target ::=
    postfix_expr


// Conceptual grammar only.
//
// The implementation uses Pratt binding powers rather than recursively
// applying this production.

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


// ------------------------------------------------------------
// UNARY EXPRESSIONS
// ------------------------------------------------------------

unary_expr ::=
    unary_op* postfix_expr

unary_op ::=
      "!"
    | "-"
    | "try"


// ------------------------------------------------------------
// POSTFIX EXPRESSIONS
//
// This is what allows arbitrary chaining:
//
// foo().bar[0].baz(x)
// ------------------------------------------------------------

postfix_expr ::=
    primary_expr postfix_part*

postfix_part ::=
      "." IDENTIFIER
    | "(" args? ")"
    | "[" expression "]"


// ------------------------------------------------------------
// PRIMARY EXPRESSIONS
// ------------------------------------------------------------

primary_expr ::=
      IDENTIFIER
    | literal
    | "(" expression ")"
    | enum_literal
    | struct_literal
    | if_expr
    | match_expr


// ------------------------------------------------------------
// ENUM LITERALS
// ------------------------------------------------------------

enum_literal ::=
    "." IDENTIFIER
    ( "(" args? ")" )?


// ------------------------------------------------------------
// STRUCT LITERALS
// ------------------------------------------------------------

// Parser-context rule:
//
// Unparenthesized struct literals are not permitted directly in
// condition position. This prevents:
//
//     if x == Point { ... }
//
// from becoming ambiguous with the following block.

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


// ------------------------------------------------------------
// ARGUMENTS
// ------------------------------------------------------------

args ::=
    expression
    ( "," expression )*
    ","?


// ------------------------------------------------------------
// LITERALS
// ------------------------------------------------------------

literal ::=
      INT
    | FLOAT
    | STRING
    | CHAR
    | "true"
    | "false"
```

---

# 34. Pratt binding powers

The parser uses this table rather than trying to encode precedence through recursive EBNF:

| Precedence | Operators              | Associativity |
| ---------: | ---------------------- | ------------- |
|          1 | `\|\|`                 | left          |
|          2 | `&&`                   | left          |
|          3 | `== !=`                | left          |
|          4 | `< > <= >=`            | left          |
|          5 | `+ -`                  | left          |
|          6 | `* / %`                | left          |
|      unary | `! - try`              | prefix        |
|    postfix | `.x`, `(...)`, `[...]` | highest       |

Pipeline sits outside the normal binary Pratt table:

```text
binary expression
        ↓
pipeline
        ↓
or recovery
```

So the rough precedence hierarchy is:

```text
or                       weakest
|
|>
|
||
|
&&
|
== !=
|
< > <= >=
|
+ -
|
* / %
|
! - try
|
.x  (...)  [...]         strongest
```

---

# 35. What happened to your original grammar?

The useful way to think about the change is not:

> “My small grammar was wrong.”

It wasn't.

It was a first model.

The progression was:

```text
Original
    ↓
Can describe simple programs

Add recursive types
    ↓
Can represent real Kō types

Add postfix expressions
    ↓
Can represent real program expressions

Introduce Pratt parsing
    ↓
Correct precedence and associativity

Separate patterns from expressions
    ↓
Matching becomes unambiguous

Make if/match expressions
    ↓
Control flow composes with expressions

Add TERM
    ↓
Source formatting and parsing agree

Add explicit mutation/assignment
    ↓
Grammar matches actual programs
```

That is precisely how language grammars tend to grow.

You start by discovering the **nouns**:

```text
function
struct
statement
expression
```

Then actual programs force you to discover the **structure inside those nouns**.

---

# 36. The five ideas I want you to understand before implementing this

### 1. Grammar recursion models recursive syntax

```ebnf
type ::= "?" type | path
```

is why:

```ko
???u64
```

could theoretically parse.

The grammar itself recursively constructs the syntax tree.

---

### 2. Postfix parsing is repeated extension

For:

```ko
foo().bar[0]
```

you don't need rules for:

```text
function_call
method_call
index_method_call
function_index_method_call
...
```

You start with:

```text
foo
```

and repeatedly attach postfix operations.

This is one of the most important simplifications in the grammar.

---

### 3. Parsing and semantic validity are different

The parser may successfully understand:

```ko
5 = x
```

as assignment-shaped syntax.

Semantic analysis then says:

> integer literal `5` is not assignable.

Don't contort every grammar production trying to encode the entire type system.

---

### 4. Pratt parsing is part of the parser, not really the EBNF

The EBNF tells you:

```text
these operators exist here
```

The Pratt parser tells you:

```text
how strongly they bind
```

That distinction will matter when you start writing `parseExpression(min_bp)`.

---

### 5. The AST should reflect meaning, not punctuation

For:

```ko
foo.bar[0]
```

your AST doesn't need nodes for:

```text
.
[
]
```

Those tokens told the parser how to construct:

```text
Index(
    Field(
        Identifier("foo"),
        "bar"
    ),
    Integer(0)
)
```

The **source syntax disappears into structure**.

That is ultimately what your parser is doing:

```text
tokens
   ↓
recognize grammatical relationships
   ↓
AST
```

The grammar is the contract in between.
