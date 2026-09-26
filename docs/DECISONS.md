# Lexer Design Decisions — Token Representation and Error Handling

## Token classification: tagged union, not plain enum

`TokenClass` is a `union(enum)`, not a plain `enum`, because some variants carry data that varies at runtime (`integer_literal`, `float_literal`) while others are pure categories with no associated value (`keyword_import`, `identifier`). A plain enum cannot express this; a tagged union stores a discriminant alongside a payload region sized to the largest variant, letting each tag opt into carrying data or not.

Nested as `Token.Tag` rather than declared at module scope. Namespacing under the type it classifies avoids polluting the top-level namespace and signals the type has no independent meaning outside `Token`.

## Payload policy: derive by default, store only what's expensive to recompute

- `identifier`, `string_literal`: no payload. Text is recovered via `Token.getLexeme(source)`, slicing `source[start..end]`. Storing the slice directly on the tag would duplicate information already recoverable from `start`/`end`, at a fixed 16-byte cost (pointer + length) on every such token regardless of whether the text is ever read.
- `integer_literal: i64`, `float_literal: f64`: payload retained. Unlike a substring, these values require actual parsing work (string-to-number conversion) to produce. Re-deriving them from source text on every access would repeat that work; storing the parsed result once is the correct tradeoff.
- `invalid`: no payload. Diagnosis of *why* a token is invalid is deferred to whatever stage reports it, using `start`/`end` to re-examine the source text on demand.

General rule applied throughout: a field earns its place only when what it stores can't be cheaply recovered from data the struct already carries elsewhere.

## Token struct shape

```zig
const Token = struct {
    start: usize,
    end: usize,
    tag: Tag,

    pub const Tag = union(enum) {
        keyword_import,
        keyword_let,
        identifier,
        string_literal,
        float_literal: f64,
        integer_literal: i64,
        invalid,
    };

    pub fn getLexeme(self: Token, source: []const u8) []const u8 {
        return source[self.start..self.end];
    }
};
```

`start`/`end` kept as loose `usize` fields rather than a nested `Span` struct — no size difference either way, but a reusable `Span` type is worth extracting once the parser or AST need the same start/end pairing, avoiding premature abstraction for a shape only one type currently uses.

## Error handling: invalid input is an ordinary tag, not an error type

The lexer's `next()` returns a plain `Token`, never an error union. A malformed byte produces a `Token` tagged `.invalid` with `start`/`end` set, flowing through the same stream as any other token. This was checked against precedent in two production compilers:

- Zig's tokenizer carries no allocator and never returns an error from scanning; it emits an `.invalid` tag and continues, deferring semantic validation (e.g., malformed literals) to a later stage.
- Rust's `rustc_lexer` is explicitly designed for error recovery, continuing to tokenize past invalid input and storing errors as flags on the token rather than reporting them from the lexer itself; validation is documented as belonging to a separate pass so the lexer stays simple and fast.

Rejected alternative: `next()` returning `!Token`, forcing every call site to `try`/`catch` on every token. This treats a routine, expected outcome of lexing arbitrary text (one bad byte) as an exceptional condition, and infects the entire parser loop with error-handling for the common case.

## Position reporting: deferred, not stored per-token

Line and column are not computed during lexing and not stored on `Token`. Rationale:

- Only tokens that actually end up being reported (a small minority) ever need line/column; computing it for every token pays a cost most tokens never use.
- A per-error, from-scratch scan of `source` counting `\n` up to `start` is correct but wasteful across multiple errors in one file, since each scan repeats work already done by prior scans.

Adopted approach: build a newline-offset table (`[]usize` of byte offsets, one pass over `source`) once, after or during lexing. Line and column for any `start` are then resolved via binary search against that table on demand, at the point a diagnostic is actually printed. This makes the fixed cost O(n) once, independent of error count, versus O(n) per error under the naive scan.

Noted counterpoint from community Jai reimplementations (not Jai's official, non-public compiler): at least two independent community projects modeling Jai's lexer store file/line/column directly on every token at lex time, trading a small fixed per-token cost for zero-lookup reporting later. Not adopted here, on the grounds that Kō's error rate is expected to be low relative to total tokens lexed, but recorded as a legitimate alternative if tooling (LSP-style live diagnostics) later needs line/column on most tokens rather than only failing ones.
