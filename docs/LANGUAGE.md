
# Kō v0 Frontend Language Contract

**Status:** implementation contract
**Scope:** lexer, parser, AST, diagnostics, and syntax-facing semantic invariants
**Non-goal:** this document does not fully specify the type system, ownership model, runtime, ABI, or standard library.

Any syntax change after this point should be deliberate and justified by an implementation or language-design problem.

---

## 1. Lexical classes

### Keywords

```text
import
struct
enum
func
let
mut
defer
return
break
continue
if
else
while
match
try
or
as
true
false
many
```

`mut` is a v0 keyword.

`as` is used for value capture.

`many` appears only in the many-item pointer form:

```ko
[*many]T
```

### Reserved for future use

```text
for
in
pub
const
union
type
```

Reserved words may not currently be used as identifiers.

### Predeclared identifiers

These are **not keywords**:

```text
u8 u16 u32 u64
i8 i16 i32 i64
f32 f64
bool
void
```

They participate in ordinary name resolution and refer to builtin types in the predeclared scope.

### Identifiers

```ebnf
IDENT ::= [A-Za-z_][A-Za-z0-9_]*
```

A lone `_` is tokenized separately as `UNDERSCORE`.

### Literals

```text
INT
FLOAT
STRING
CHAR
```

Examples:

```ko
123
0xFF
0b1010
1_000

1.5
2e10

"hello\n"

'x'
```

### Operators

```text
+  -  *  /  %
== != < > <= >=
&& || !
= += -= *= /=
|>
```

### Punctuation

```text
( ) { } [ ]
, : ; .
#
=>
?
```

### Trivia

Whitespace and comments are discarded by the lexer except where a newline may produce `TERM`.

```ko
// line comment

/* block comment */
```

### Lexer policy

The lexer uses **maximal munch**.

Examples:

```text
=> before =
>= before >
!= before !
|| before |
|> before |
```

---

## 2. Statement termination

Kō permits both explicit semicolons and significant newlines.

```text
TERM ::= ";" | inserted-newline
```

A newline becomes `TERM` when the previous significant token can legally terminate an expression or statement.

Initial v0 terminators include:

```text
IDENT
INT FLOAT STRING CHAR
true false
)
]
}
return
break
continue
```

The parser may ignore a `TERM` immediately before:

```text
}
)
]
EOF
```

The rule must remain deterministic and lexer-driven.

---

## 3. Types

```ebnf
type ::=
      "!" type
    | "?" type
    | "[" "]" type
    | "*" type
    | "[" "*" "many" "]" type
    | path
```

Examples:

```ko
u64
mem.Allocator

[]u8
[][]u8

?[]u8
!?[]u8

*Stats
[*many]u8
```

### Type meanings

```ko
*T
```

Pointer to one object.

Pointer arithmetic is not permitted.

```ko
[]T
```

Slice containing a reference to contiguous elements together with a known length.

```ko
[*many]T
```

Many-item pointer.

The value carries no length. Indexing and pointer arithmetic may therefore rely on validity guarantees supplied externally.

This form is intentionally more verbose than ordinary pointers because it represents a loss of bounds information.

```ko
?T
```

Optional value.

```ko
!T
```

Fallible value.

Types compose recursively:

```ko
!?[]u8
```

means a fallible optional slice.

---

## 4. Top-level declarations

```ebnf
program       ::= ( declaration | TERM )* EOF

declaration   ::=
      import_decl
    | struct_decl
    | enum_decl
    | func_decl

import_decl   ::= "import" path

path          ::= IDENT ( "." IDENT )*
```

Example:

```ko
import std.io
```

---

## 5. Directives

```ebnf
directive ::= "#" IDENT ( "(" args ")" )?
```

Directives are syntactically recognized in v0 even if only a small subset is semantically implemented.

Example:

```ko
#repr(C)
struct Header {
    ...
}
```

---

## 6. Structs and enums

```ebnf
struct_decl ::= "struct" IDENT directive* "{" field_list? "}"

field_list ::= field ( "," field )* ","?

field ::= directive* IDENT ":" type
```

Example:

```ko
struct Stats {
    valid: u64,
    corrupt: u64,
    total: f64,
}
```

Enums:

```ebnf
enum_decl ::= "enum" IDENT directive* "{" variant_list? "}"

variant_list ::= variant ( "," variant )* ","?

variant ::= IDENT ( "(" field_list ")" )?
```

Example:

```ko
enum Row {
    Valid(id: u64, amount: f64),
    Incomplete(reason: []u8),
    Corrupt,
}
```

---

## 7. Functions

```ebnf
func_decl ::= "func" IDENT "(" param_list? ")" type? block

param_list ::= param ( "," param )* ","?

param ::= "mut"? IDENT ":" type
```

If the return type is omitted, it is `void`.

Examples:

```ko
func reset(mut s: Stats) {
    ...
}

func parse(line: []u8) Row {
    ...
}

func read() !?[]u8 {
    ...
}
```

A `mut` parameter represents temporary mutable access to the supplied value.

It is not a general first-class reference and may not itself be stored or returned.

---

## 8. Blocks and statements

```ebnf
block ::= "{" ( statement | TERM )* "}"

statement ::=
      let_stmt
    | assign_stmt
    | defer_stmt
    | return_stmt
    | flow_stmt
    | while_stmt
    | expr_stmt

let_stmt ::= "let" "mut"? IDENT ( ":" type )? "=" expression

assign_stmt ::= postfix assign_op expression

defer_stmt ::= "defer" statement

return_stmt ::= "return" expression?

flow_stmt ::= "continue" | "break"

expr_stmt ::= expression
```

Examples:

```ko
let count = 0

let mut count: u64 = 0

count += 1

defer file.close()

return value
```

Variables must be initialized when declared.

---

## 9. Mutation

Mutable local bindings use:

```ko
let mut x = value
```

Mutable parameters use:

```ko
func update(mut x: T) {
    ...
}
```

Ordinary values are immutable by default.

General pointer-based mutation is not the default mutation mechanism.

---

## 10. Control flow

### While

```ebnf
capture ::= "as" IDENT

while_stmt ::= "while" expression capture? block
```

Example:

```ko
while try reader.read_line() as line {
    process(line)
}
```

When the expression produces `?T`, capture unwraps the present value.

The loop terminates when the optional is empty.

---

### If

`if` is an expression.

```ebnf
if_expr ::=
    "if" expression capture? block
    ( "else" capture? ( if_expr | block ) )?
```

Examples:

```ko
if ready {
    run()
}
```

and:

```ko
if result as value {
    use(value)
} else {
    fallback()
}
```

Exact capture semantics depend on the type of the condition and are validated during semantic analysis.

---

### Match

```ebnf
match_expr ::=
    "match" expression "{"
        ( match_arm ( "," match_arm )* ","? )?
    "}"

match_arm ::=
    pattern
    ( "if" expression )?
    "=>"
    ( block | expression )
```

Example:

```ko
match row {
    .Valid(id, amount) => process(id, amount),
    .Incomplete(why)   => review(why),
    .Corrupt           => {},
}
```

Matches over closed sum types must be exhaustive.

---

## 11. Patterns

```ebnf
pattern ::=
      "_"
    | literal
    | IDENT
    | "." IDENT ( "(" pattern_list ")" )?

pattern_list ::= pattern ( "," pattern )* ","?
```

A bare identifier is a binding:

```ko
value
```

An enum variant requires a leading dot:

```ko
.Valid
.Valid(id, amount)
```

This avoids ambiguity between bindings and variant names.

---

## 12. Expressions

```ebnf
expression ::= pipe ( "or" fallback )?

fallback ::= return_stmt | flow_stmt | block | expression

pipe ::= binary ( "|>" pipe_target )*

pipe_target ::= postfix

binary ::= unary ( bin_op unary )*

unary ::= ( "!" | "-" | "try" )* postfix

postfix ::=
    primary
    (
        "." IDENT
      | "(" args? ")"
      | "[" expression "]"
    )*

primary ::=
      IDENT
    | literal
    | "(" expression ")"
    | enum_lit
    | struct_lit
    | if_expr
    | match_expr

enum_lit ::= "." IDENT ( "(" args? ")" )?

args ::= expression ( "," expression )* ","?

literal ::= INT | FLOAT | STRING | CHAR | "true" | "false"
```

---

## 13. Operator precedence

All binary operators are left-associative.

From lowest to highest:

| Level   | Operators              |    |   |
| ------- | ---------------------- | -- | - |
| 1       | `                      | >` |   |
| 2       | `                      |    | ` |
| 3       | `&&`                   |    |   |
| 4       | `== !=`                |    |   |
| 5       | `< > <= >=`            |    |   |
| 6       | `+ -`                  |    |   |
| 7       | `* / %`                |    |   |
| unary   | `! - try`              |    |   |
| postfix | `.x`, `(...)`, `[...]` |    |   |

Examples:

```ko
a + b * c
```

parses as:

```ko
a + (b * c)
```

and:

```ko
value + 1 |> transform
```

parses as:

```ko
transform(value + 1)
```

---

## 14. Pipeline operator

```ko
value |> f
```

is equivalent to:

```ko
f(value)
```

and:

```ko
value |> f(a, b)
```

is equivalent to:

```ko
f(value, a, b)
```

The operator expresses ordinary function application only.

It does not create an independent concurrency, streaming, or lazy-evaluation model.

---

## 15. Error handling

Fallible values use:

```ko
!T
```

`try` propagates the error:

```ko
let file = try io.open(path)
```

Conceptually:

```text
!T -> T
```

on success, otherwise the enclosing function returns the error.

### Recovery with `or`

`or` handles failure locally.

Example:

```ko
let id = u64.parse(text) or return .Invalid
```

The left-hand side must be a fallible expression.

On success, its payload becomes the expression value.

On failure, the fallback expression executes.

This deliberately separates two common intentions:

```ko
try operation()
```

means:

> propagate the failure.

while:

```ko
operation() or ...
```

means:

> handle the failure here.

`or` is not boolean OR.

Boolean OR is:

```ko
||
```

---

## 16. Struct literals

```ebnf
struct_lit ::= path "{" struct_init_list? "}"

struct_init_list ::= struct_init ( "," struct_init )* ","?

struct_init ::= IDENT ":" expression
```

Example:

```ko
Stats {
    valid: 0,
    corrupt: 0,
    total: 0.0,
}
```

To avoid ambiguity between block syntax and struct construction, an unparenthesized struct literal is not permitted directly in condition position.

Use:

```ko
if (make() == Point { x: 1, y: 2 }) {
    ...
}
```

rather than relying on ambiguous parsing.

---

## 17. Integer literals and numeric coercion

Unsuffixed numeric literals begin without a fixed concrete integer or floating-point type.

Their type is resolved from context when possible.

Examples:

```ko
let x: u64 = 1
amount < 0
stats.total += 1
```

Implicit numeric conversion must never silently discard information.

Lossy or narrowing conversions require explicit conversion APIs.

---

## 18. Integer overflow

Ordinary integer arithmetic must never silently wrap.

In checked/debug execution, overflow traps.

Wrapping arithmetic, if exposed in v0, must use explicit operators or explicit builtin operations.

Silent C-style overflow is not part of the language contract.

The exact spelling of explicit wrapping arithmetic may remain outside the initial frontend milestone until the first arithmetic semantic pass requires it.

---

## 19. Memory-facing frontend rules

The frontend recognizes three major reference-like forms:

```ko
*T
[]T
[*many]T
```

They intentionally preserve different amounts of information.

```text
*T        one object
[]T       contiguous values + known length
[*many]T  contiguous values + unknown length
```

The language should prefer slices where bounds are known.

Many-item pointers exist for low-level work such as runtime implementation and FFI and should remain uncommon in ordinary application code.

---

## 20. Arena syntax

`arena` is **not part of the frozen v0 frontend grammar**.

Previous forms such as:

```ko
arena as a {
    ...
}
```

remain design experiments.

Allocator and arena behavior should initially be expressed through ordinary library values and `defer`.

Example:

```ko
let arena = mem.Arena.init()
defer arena.free()
```

A dedicated lexical arena construct may be reconsidered only after implementation experience demonstrates a concrete benefit.

---

## 21. AST contract

AST node vocabulary must correspond directly to grammar concepts.

The frontend uses a data-oriented AST representation.

Nodes are stored in a flat arena and reference other nodes using integer indices rather than heap pointers.

Conceptually:

```text
NodeId = u32
```

Source spans are stored separately from node payloads.

Conceptually:

```text
nodes : []Node
spans : []Span
```

with matching indices.

A source span is:

```text
start: u32
end:   u32
```

This keeps syntax nodes compact while preserving complete diagnostic information.

---

## 22. Diagnostics

Every parser diagnostic should contain at minimum:

```text
primary source span
short error message
expected syntax where meaningful
```

Example style:

```text
error: expected expression after `=`

    let value =
                ^
```

Diagnostics should prefer teaching the programmer what the parser expected rather than merely reporting an internal parser state.

Recovery should attempt to synchronize around obvious boundaries such as:

```text
TERM
}
,
EOF
```

---

## 23. Parsing strategy

The parser is recursive descent for declarations, statements, blocks, types, and control-flow constructs.

Expressions use Pratt parsing.

Postfix operations are parsed as repeated extensions of a primary expression:

```ko
a.b()[0].c(x)
```

This must remain representable without special-case method-call productions.

Assignment is parsed only after a valid assignable postfix expression has been recognized.

Semantic analysis later validates whether the left-hand side is actually mutable and assignable.

---

## 24. Explicitly deferred from v0 frontend design

The following must not block the first frontend implementation:

```text
generics
macros
operator overloading
classes/inheritance
compile-time execution
region/lifetime checking
arena escape analysis
full unsafe-block semantics
custom operators
user-defined implicit conversions
```

They may be revisited only when concrete language programs demonstrate the need.

---

## 25. Frontend implementation order

The contract should be implemented in this order:

```text
1. Token definitions
2. Lexer
3. Lexer tests
4. AST storage
5. Basic recursive-descent parser
6. Pratt expression parser
7. Parser tests
8. Source-span propagation
9. Diagnostic rendering
10. Name resolution
```

The type checker should not drive further syntax design until the parser can successfully represent non-trivial Kō programs.

---

# Freeze Rule

From this point forward:

> Syntax does not change merely because another spelling looks nicer.

A frontend syntax change should answer at least one concrete problem involving:

* ambiguity,
* implementation complexity,
* semantic inconsistency,
* safety,
* readability in real programs, or
* inability to express an intended language feature.

Otherwise, the existing rule wins.

The goal of v0 is not to discover the perfect syntax.

The goal is to build enough of Kō that its deeper ideas can be tested in real programs.
