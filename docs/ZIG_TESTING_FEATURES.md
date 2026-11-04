# Zig Testing Features Used in This Project

This document explains the Zig testing features used by the tokenizer tests in
`src/tokenizer.zig` and how they fit together with `build.zig`.

## Test blocks

Zig defines a test with a `test` declaration:

```zig
test "lexer: keywords" {
    // test code
}
```

The string is the test name shown by the test runner. The body can return an
error, so assertions are normally written with `try`:

```zig
test "a test can fail" {
    try std.testing.expectEqual(@as(u8, 2), 1 + 1);
}
```

The tokenizer file contains several named tests. Running:

```sh
zig test src/tokenizer.zig
```

compiles that file as the test root and runs its test declarations.

## Importing tests from another file

`src/main.zig` is one of this project's test roots. It explicitly includes the
tokenizer tests:

```zig
test {
    _ = @import("./tokenizer.zig");
}
```

This is an unnamed top-level test block. The `_ =` expression is a deliberate
compile-time reference that tells Zig to discover the imported file's tests.

The path is relative to `src/main.zig`; therefore `./tokenizer.zig` is correct.

Reference:

- [Zig language reference: Test Blocks](https://ziglang.org/documentation/0.17.0/#Test-Blocks)

## `std.testing`

The tests import the standard library:

```zig
const std = @import("std");
```

Then they use `std.testing` for assertions. This namespace provides test
allocators, assertions, and test-related helpers.

### `expect`

`expect` checks a boolean condition:

```zig
try std.testing.expect(token.end > token.start);
```

If the condition is false, the test returns an error and Zig reports the test
as failed.

### `expectEqual`

`expectEqual` compares two values and prints both the expected and actual values
when they differ:

```zig
try std.testing.expectEqual(Token.Tag.keyword_let, actual.tag);
try std.testing.expectEqual(@as(u32, 2), actual.start);
```

The explicit `@as` is useful when Zig cannot infer the intended integer type
from a literal.

For tokenizer tests, comparing `tag`, `start`, and `end` separately makes a
failure precise. It tells us whether recognition or span calculation is
wrong.

## Tests that return errors

Zig test bodies commonly return an inferred error union. This allows helper
functions to return errors too:

```zig
fn testTokenize(
    source: [:0]const u8,
    expected: []const Token,
) !void {
    try std.testing.expectEqual(...);
}
```

The calling test propagates the helper's failure with `try`:

```zig
test "lexer: punctuation" {
    try testTokenize("(", &.{
        .{ .tag = .l_paren, .start = 0, .end = 1 },
    });
}
```

This keeps helpers small and lets the test runner report the failing test and
source location.

## Table-driven tests

Many tokenizer behaviours have the same shape: input, expected tag, and
expected span. Instead of writing one test body for every word, the tests store
cases in a tuple collection:

```zig
const cases = .{
    .{ "let", Token.Tag.keyword_let },
    .{ "mut", Token.Tag.keyword_mut },
    .{ "return", Token.Tag.keyword_return },
};
```

Then they iterate over the cases:

```zig
for (cases) |case| {
    try expectTokenSequence(case[0], &.{
        .{ .tag = case[1], .start = 0, .end = @intCast(case[0].len) },
    });
}
```

This style is useful because adding another keyword or operator requires adding
one row rather than duplicating assertion logic.

The cases use an ordinary `for` loop. The table is data used by the test at
runtime; there is no need to unroll these checks at compile time. This keeps the
test pattern explicit and avoids adding a metaprogramming feature where it does
not improve readability.

## Sentinel-terminated strings

`Tokenizer.init` accepts:

```zig
[:0]const u8
```

This is a slice of bytes with a guaranteed zero sentinel immediately after the
source contents. String literals naturally work as sentinel-terminated slices:

```zig
const source: [:0]const u8 = "let";
```

The sentinel is not part of `source.len`. For `"let"`:

```text
source bytes: l e t
indexes:       0 1 2 3
                         sentinel
source.len == 3
```

The tokenizer uses the distinction between `self.index == self.buffer.len` and
an embedded zero byte to distinguish EOF from invalid input.

## Exact span assertions

Token spans use half-open ranges:

```text
[start, end)
```

For `"let"`, the expected token is:

```text
start = 0
end   = 3
```

The byte at `end` is not part of the token. The helper `testTokenize` checks
both the expected tokens and the final EOF token:

```zig
try std.testing.expectEqual(want.start, actual.start);
try std.testing.expectEqual(want.end, actual.end);

const eof = tokenizer.next();
const end: u32 = @intCast(source.len);
try std.testing.expectEqual(Token.Tag.eof, eof.tag);
try std.testing.expectEqual(end, eof.start);
try std.testing.expectEqual(end, eof.end);
```

Checking spans prevents a tokenizer from returning the right tag while
silently consuming bytes belonging to the next token.

## Bounded progress tests

The tokenizer must eventually return EOF. A broken state machine could loop
forever, so the tests impose a maximum number of calls:

```zig
const max_calls = source.len + 1;
```

The extra one allows for the final EOF call. Every non-EOF token must satisfy:

```zig
try std.testing.expect(token.end > token.start);
```

The test also checks that spans remain inside the source:

```zig
try std.testing.expect(token.end <= source.len);
```

If EOF is not reached before the bound, the test fails instead of hanging:

```zig
try std.testing.expect(false);
```

This is especially valuable for invalid bytes and incomplete operator states.

## Exhaustive single-byte testing

The tokenizer has a test for every byte value from `0x00` through `0xff`:

```zig
var value: u16 = 0;
while (value <= 0xff) : (value += 1) {
    var source: [1:0]u8 = .{@intCast(value)};
    try expectProgress(source[0..]);
}
```

`u16` is used for the loop counter so that the value can represent `0xff` and
then increment to `0x100` without overflowing an 8-bit integer.

This test does not require every byte to be a valid language token. It checks
the safety and progress contract for every possible one-byte input.

## Generated short inputs

The tests also generate all inputs of lengths zero through three over a fixed
alphabet:

```zig
const alphabet = [_]u8{
    0x00, 0x01, 0x7f, 0x80, 0xff,
    ' ', '\n', 'a', 'Z', '_', '0',
    '!', '|', '&', '=', '+', '-', '*', '/', '%', '<', '>',
};
```

Nested loops build every combination. These generated tests check general
invariants rather than one exact tokenization for every input:

- tokens have monotonic positions;
- spans stay inside the source;
- non-EOF tokens consume at least one byte;
- EOF is eventually reached;
- the call count stays bounded.

This gives broad coverage without requiring a manually written expected token
list for thousands of byte strings.

## Test filters

Zig can run a subset of tests by name:

```sh
zig test src/tokenizer.zig --test-filter invalid
```

The filter matches test names containing the supplied text. In this project it
selects the invalid-byte tests, which is useful when debugging a focused
failure.

The same option is used by the Zed debug configuration so the debugger starts
only the relevant tokenizer tests.

## Debug versus test execution

These commands have different purposes:

```sh
zig test src/tokenizer.zig
```

Compile and run the tokenizer tests directly.

```sh
zig build test --summary all
```

Run all test executables connected to the project's build graph.

```sh
zig test src/tokenizer.zig \
  --test-filter invalid \
  -femit-bin=zig-out/bin/tokenizer-tests \
  --test-cmd true \
  --test-cmd-bin
```

Compile a filtered test executable without running it, so Zed can launch it
under LLDB.

## Safety checking

Zig's Debug mode keeps runtime safety checks enabled. These checks can catch
mistakes such as:

- indexing beyond the sentinel-terminated buffer;
- invalid slice bounds;
- integer overflow in safety-checked contexts;
- sentinel mismatches;
- unreachable conditions being reached.

The generated-input tests intentionally run under these checks. A panic is
useful evidence: it means the test found a state-machine path that violated a
memory or sentinel assumption.

## Test output and failure interpretation

A failing assertion reports an expected/actual difference and a source line.
For example:

```text
expected .invalid, found .keyword_let
```

That identifies the observable error. A debugger can then be used to inspect
the transition that produced it.

The recommended workflow is:

1. Run the focused test with `--test-filter`.
2. Read the expected/actual values and source line.
3. Set a breakpoint near the relevant tokenizer state.
4. Run the filtered test under Zed/LLDB.
5. Inspect `self.index`, `result.start`, `result.end`, and `result.tag`.
6. Fix the smallest state-machine transition that violates the contract.
7. Run the focused test again, then run the complete build test command.

## Documentation links

- [Zig 0.17.0 language reference](https://ziglang.org/documentation/0.17.0/)
- [Zig Test Blocks](https://ziglang.org/documentation/0.17.0/#Test-Blocks)
- [Zig command-line options](https://ziglang.org/documentation/0.17.0/#Command-Line-Options)
- [Zig testing examples](https://ziglang.org/documentation/0.17.0/#Testing)
- [Zed Debugger](https://zed.dev/docs/debugger)
