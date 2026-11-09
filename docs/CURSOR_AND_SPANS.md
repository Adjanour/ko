# Cursor and Half-Open Spans

When the tokenizer reads source code, it uses a **cursor** to remember where
it is in the input. In Kō, this cursor is the `index` field. It points to the
next byte that the tokenizer should inspect.

## The cursor

Suppose the source is:

```text
hello
```

The bytes have zero-based positions:

```text
h e l l o
0 1 2 3 4
```

If the cursor is `0`, it is looking at `h`. After consuming `h`, the
tokenizer increments the cursor to `1`, so it now points at `e`. The cursor
always marks the next unread position.

## Half-open spans

Each token records two positions:

```text
[start, end)
```

The `start` position is included, but the `end` position is excluded. The
`end` position is therefore one byte past the final byte belonging to the
token.

For example, the token `ell` in `hello` has this span:

```text
[1, 4)
```

It includes positions `1`, `2`, and `3`, but not position `4`.

## Consuming characters

The tokenizer usually begins a token by saving the current cursor as
`start`. Each time it consumes a byte, it increments the cursor. When the
token is complete, the cursor has moved just past the token, so its value is
used as `end`.

For a one-byte token at position `2`:

```text
start = 2
end   = 3
```

This gives the span `[2, 3)`.

## Calculating length

Because `end` is one position past the token, the token's length is simply:

```text
length = end - start
```

For `[1, 4)`, the length is `4 - 1 = 3`.

This convention also makes source slicing direct:

```zig
source[token.start..token.end]
```

The slice includes the token's bytes and stops before `end`.
