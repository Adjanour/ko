# Debugging Zig with Zed

This guide explains both what a debugger does and how this repository uses Zed
to debug the tokenizer tests.

## What a debugger is

A program normally runs continuously:

```text
start -> execute instructions -> exit
```

A debugger pauses that running program so you can inspect its state and control
what happens next:

```text
start -> breakpoint -> inspect -> step -> continue -> exit
```

When debugging `Tokenizer.next()`, useful values include:

- `self.index`: the next input byte to inspect;
- `self.buffer`: the sentinel-terminated input buffer;
- `result.start`: the beginning of the current token;
- `result.end`: the token's exclusive end position;
- `result.tag`: the token classification.

For an invalid byte, the M1 contract is:

```text
end == start + 1
```

The debugger lets you watch that invariant while the tokenizer executes.

## Debugger vocabulary

### Breakpoint

A breakpoint tells the debugger to pause when execution reaches a source line
or function. In Zed, click beside a line number in the editor gutter.

Useful tokenizer locations are the `.start` state, the `.invalid` state, and
the common return at the end of `Tokenizer.next()`.

### Continue

Resume execution until another breakpoint, a test failure, or program exit.

### Step over

Execute the current source line without entering a function called by that
line.

### Step into

Enter a function called by the current line.

### Step out

Finish the current function and pause when control returns to its caller.

### Call stack

The call stack shows how execution reached the current line. A tokenizer test
may have a stack like:

```text
lexer: invalid bytes advance one byte at a time
  -> testTokenize
     -> Tokenizer.next
```

Selecting a caller frame lets you inspect that caller's variables.

### Locals and watches

Locals are variables in the current function. Useful watch expressions here
include:

```text
self.index
self.buffer.len
result.start
result.end
result.tag
```

## How source-level debugging works

The processor executes machine instructions, not Zig source lines. A Debug
build contains debug information that maps:

```text
machine instruction -> source file -> source line -> variables and types
```

That mapping lets LLDB report that the process is stopped at a particular line
in `src/tokenizer.zig` and display values such as `self.index`.

Optimized builds can make this mapping less predictable: variables may be
removed or moved, and several source lines may become one machine instruction.
Zig's default Debug mode is the appropriate mode for learning and stepping.

## The debugger components

The debugging stack is layered:

```text
Zed editor
    |
    | Debug Adapter Protocol (DAP)
    v
CodeLLDB / LLDB debug adapter
    |
    v
LLDB debugger
    |
    v
tokenizer-tests executable
```

### Zed

Zed provides the interface: breakpoints, stepping controls, the call stack,
locals, and debug output.

### Debug Adapter Protocol

DAP is a standard message protocol between an editor and a debugger adapter.
Zed can send generic requests such as:

```text
set breakpoint
launch program
continue
step over
read local variable
```

### CodeLLDB and LLDB

The adapter translates DAP requests into LLDB operations. LLDB controls the
actual process: it launches it, pauses it, resumes it, and reads its memory,
stack, registers, and debug information.

## This repository's Zed configuration

The project configuration is in:

```text
.zed/debug.json
```

Its important fields are:

```json
{
  "label": "Debug tokenizer invalid-byte tests",
  "adapter": "CodeLLDB",
  "request": "launch",
  "program": "$ZED_WORKTREE_ROOT/zig-out/bin/tokenizer-tests",
  "cwd": "$ZED_WORKTREE_ROOT"
}
```

### `label`

The name displayed in Zed's debug-session picker.

### `adapter`

The LLDB-based adapter Zed uses to communicate with the debugger.

### `request`

`launch` tells Zed to start a new process. This is appropriate for tests,
because each debugging session should start with a fresh test process.

### `program`

This is the compiled executable that LLDB launches. It is not the Zig source
file. The source file is connected through debug information embedded in the
executable.

### `cwd`

The process working directory. `$ZED_WORKTREE_ROOT` expands to the repository
root opened in Zed.

## How the build task works

Before launching LLDB, Zed runs:

```sh
zig test src/tokenizer.zig \
  --test-filter invalid \
  -femit-bin=zig-out/bin/tokenizer-tests \
  --test-cmd true \
  --test-cmd-bin
```

The options mean:

### `zig test src/tokenizer.zig`

Compile the tokenizer as a test root, including its test blocks and Zig's test
runner.

### `--test-filter invalid`

Select tests whose names contain `invalid`. This keeps the session focused on
the two invalid-byte tests.

### `-femit-bin=zig-out/bin/tokenizer-tests`

Write the compiled test executable to the path named by `program` in the Zed
configuration.

### `--test-cmd true --test-cmd-bin`

Normally `zig test` both compiles and runs the test executable. A failing test
would make that command exit before Zed could start LLDB. These options tell
Zig to emit the binary without running its tests as part of the build task.

The sequence is therefore:

```text
Zed build task -> compile test binary
Zed debugger   -> launch test binary under LLDB
```

## Starting a session in Zed

1. Open `src/tokenizer.zig`.
2. Click beside a line in the `.invalid` state.
3. Press **F4**, or run **Debugger: Start**.
4. Select **Debug tokenizer invalid-byte tests**.
5. Wait for the build task to finish.
6. Use Continue, Step Over, Step Into, and Step Out.

While stopped, inspect:

```text
self.index
self.buffer.len
result.start
result.end
result.tag
```

## Walking through the invalid-byte bug

For input `"$"`, the conceptual buffer is:

```text
index:  0    1
byte:  '$'  '\0'
       source sentinel
```

At the beginning of `next()`:

```text
result.start = 0
self.index = 0
```

The fixed invalid state does this:

```zig
.invalid => {
    result.tag = .invalid;
    self.index += 1;
},
```

After stepping over the increment:

```text
self.index = 1
result.start = 0
```

The common return code then produces:

```text
invalid [0,1)
```

For `"@@@"`, repeated calls should produce:

```text
invalid [0,1)
invalid [1,2)
invalid [2,3)
eof     [3,3)
```

The EOF token may have an empty span because it represents the position after
the final source byte. Invalid tokens may not have empty spans.

## Debugging the test call stack

When a breakpoint hits inside `Tokenizer.next()`, the current frame is the
tokenizer. The caller is typically `testTokenize` or the repeated-call test.

Moving up one frame shows:

- which test case is running;
- the expected token data;
- how many tokens have already been consumed.

This is useful when the same tokenizer function is called repeatedly with
different inputs. The call stack tells you which test invocation caused the
breakpoint.

## Debugger versus failed assertions

A failed assertion tells you what differed:

```text
expected invalid [0,1), found invalid [1,1)
```

A debugger tells you how it happened:

```text
result.start was initialized to 0
self.index advanced to 1
an early return constructed a new token starting at 1
```

Use test output to identify the mismatch, then use the debugger to inspect the
state transitions that produced it.

## Common problems

### Breakpoint never hits

Check that:

- the tokenizer debug configuration was selected;
- `program` matches the emitted binary;
- the test filter includes the test;
- the source file used by Zed matches the file used to compile the binary;
- the build is using Debug mode.

### The build task fails before the debugger starts

Confirm that the configuration includes:

```text
--test-cmd true --test-cmd-bin
```

Without those options, a failing test exits before Zed can launch LLDB.

### Variables are unavailable

Use Debug optimization. Release optimizations can remove, combine, or move
variables and can make source stepping confusing.

### Zed cannot find CodeLLDB

The CodeLLDB adapter must be installed or available to Zed. This project also
has `lldb-dap` available on the command line, but the adapter name in
`.zed/debug.json` must match an adapter known to Zed.

## Documentation links

- [Zed Debugger](https://zed.dev/docs/debugger)
- [Zed debugger configuration](https://zed.dev/docs/debugger#configuration)
- [Debug Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/)
- [LLDB tutorial](https://lldb.llvm.org/use/tutorial.html)
- [Zig 0.17.0 language reference](https://ziglang.org/documentation/0.17.0/)
- [Zig test blocks](https://ziglang.org/documentation/0.17.0/#Test-Blocks)
- [Zig command-line options](https://ziglang.org/documentation/0.17.0/#Command-Line-Options)
