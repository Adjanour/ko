# Understanding `build.zig` and the Test Graph

This project uses Zig's build system to compile the program and connect its
tests to the normal command:

```sh
zig build test
```

The tokenizer tests live in `src/tokenizer.zig`, but the test executable is
rooted at `src/main.zig`. `src/main.zig` explicitly includes the tokenizer's
tests:

```zig
test {
    _ = @import("./tokenizer.zig");
}
```

The import path is relative to `src/main.zig`, so `./tokenizer.zig` is correct;
`src/tokenizer.zig` would be the wrong path there.

## Why the `test` block matters

An ordinary import makes a file available to the program, but a test file's
test declarations should be explicitly referenced from a top-level test block
when the goal is to ensure those tests run:

```zig
test {
    _ = @import("./tokenizer.zig");
}
```

The `_ =` expression is a compile-time no-op reference. It tells Zig to
discover the imported file while compiling tests. The tokenizer tests are
then included in the test executable rooted at `src/main.zig`.

This is the official pattern documented under *Force file discovery with
comptime and test blocks*:

- [Zig language reference: `test` blocks and forced file discovery](https://ziglang.org/documentation/0.17.0/#Test-Blocks)

## The important parts of `build.zig`

### 1. Build options

```zig
const target = b.standardTargetOptions(.{});
const optimize = b.standardOptimizeOption(.{});
```

These expose standard command-line options such as `-Dtarget` and
`-Doptimize`. The rest of the build graph can use those values so that the
executable and tests target the same platform and optimization mode.

### 2. Modules

```zig
const mod = b.addModule("ko", .{
    .root_source_file = b.path("src/root.zig"),
    .target = target,
});
```

A module is a collection of Zig source files with a root source file and
compilation settings. Here, `src/root.zig` is the reusable `ko` module.

The executable's module imports it under the name `ko`:

```zig
.imports = &.{
    .{ .name = "ko", .module = mod },
},
```

### 3. The executable

```zig
const exe = b.addExecutable(.{
    .name = "ko",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ko", .module = mod },
        },
    }),
});
```

This creates the `ko` executable with `src/main.zig` as its root. The call to
`b.installArtifact(exe)` makes the default `zig build` command install the
executable into `zig-out/`.

Relevant reference:

- [Zig build system documentation](https://ziglang.org/documentation/0.17.0/#Build-System)

### 4. The `run` step

```zig
const run_step = b.step("run", "Run the app");
const run_cmd = b.addRunArtifact(exe);
run_step.dependOn(&run_cmd.step);
```

`b.step` creates a named top-level command. `b.addRunArtifact(exe)` creates a
step that runs the executable. The dependency means:

```sh
zig build run
```

builds and runs `ko`.

### 5. Test executables

The build script creates two test executables:

```zig
const mod_tests = b.addTest(.{
    .root_module = mod,
});
const run_mod_tests = b.addRunArtifact(mod_tests);

const exe_tests = b.addTest(.{
    .root_module = exe.root_module,
});
const run_exe_tests = b.addRunArtifact(exe_tests);
```

Each call to `b.addTest` chooses one test root:

```text
mod_tests  -> src/root.zig
exe_tests  -> src/main.zig
                         └── ./tokenizer.zig tests
```

The executable-rooted test binary contains the tokenizer tests because
`src/main.zig` references `./tokenizer.zig` from its top-level `test` block.

### 6. The normal `test` command

```zig
const test_step = b.step("test", "Run tests");
test_step.dependOn(&run_mod_tests.step);
test_step.dependOn(&run_exe_tests.step);
```

The `test` step itself does not run anything until it has dependencies. These
two dependencies connect both test-running steps to:

```sh
zig build test
```

The resulting graph is:

```text
zig build test
└── test step
    ├── run_mod_tests
    │   └── test executable rooted at src/root.zig
    └── run_exe_tests
        └── test executable rooted at src/main.zig
            └── tokenizer tests imported by a top-level test block
```

Build steps are graph nodes. `dependOn` creates edges between them; it does
not directly execute the dependency while `build.zig` is being evaluated.
Zig evaluates the graph later, when the requested top-level step is run.

## How to verify the graph

Use the summary option because a successful `zig build test` may otherwise
produce no output:

```sh
zig build test --summary all
```

The current project reports five tests: one from `src/root.zig` and four from
`src/tokenizer.zig`.

To see the compiler commands and their test roots:

```sh
zig build test --verbose --summary all
```

You should see test commands rooted at both `src/root.zig` and
`src/main.zig`.

To run the tokenizer test file directly, bypassing the build graph:

```sh
zig test src/tokenizer.zig
```

## Proving the connection

A successful test run alone does not prove that a particular test file is
connected. Temporarily change one tokenizer expectation, for example:

```zig
try std.testing.expectEqual(Token.Tag.identifier, token.next().tag);
```

when the actual expected token is `keyword_else`. Then run:

```sh
zig build test --summary all
```

The normal command fails and reports the tokenizer test. Restore the correct
expectation and rerun both commands:

```sh
zig build test --summary all
zig test src/tokenizer.zig
```

Both commands should pass, and the direct tokenizer command should report all
eighteen tokenizer tests.

## Useful Zig documentation

- [Zig 0.17.0 language reference](https://ziglang.org/documentation/0.17.0/)
- [Build System](https://ziglang.org/documentation/0.17.0/#Build-System)
- [Test Blocks](https://ziglang.org/documentation/0.17.0/#Test-Blocks)
- [Testing](https://ziglang.org/documentation/0.17.0/#Testing)
- [Build system example in the Zig standard library repository](https://github.com/ziglang/zig/tree/master/lib/libc)
