# Kō Learning and Build Plan

**Status:** active working plan  
**Owner:** Bernard  
**Current milestone:** M1 — a reliable, tested tokenizer boundary  
**Target window:** 19–25 October 2026; closure gates take precedence over the date  
**Working rhythm:** one protected 05:00–07:00 session each day

## Next action — 19 October, 05:00

1. Open `build.zig` at the current failure around line 114.
2. Write this question on paper: **How does Zig 0.17 pass command-line arguments to a run artifact now that `Build.args` is unavailable?**
3. Run `zig build test` once and keep the exact first error visible.
4. Read only the relevant Zig 0.17 build API or implementation until I can explain the replacement.
5. Make the smallest hand-written build-script change and rerun the same command.

Do not edit the tokenizer during this session until the build graph loads. The exit condition is not “everything passes”; it is “the build API failure is gone and the next failure is honestly exposed.”

- solved the build api failure has been fixed. We now use std.Build.Step.Run.addPassthruArgs which automatically integrates all the arguments after '--' passed in the cli into the run step

## 1. The point of this project

Kō is a project for learning by building.

The goal is not to produce a perfect language or compiler from imagination. The goal is to become a stronger programmer by repeatedly turning an idea into a small implementation, observing where it fails, understanding why, repairing it, and explaining what was learned.

Kō should help me:

- learn Zig through real work rather than disconnected exercises;
- understand how programming languages work from source text through later compiler stages;
- develop intuition for state, memory, data representation, parsing, diagnostics, testing, and correctness;
- practice finishing bounded components instead of continuously redesigning the whole language;
- become comfortable with failure as information rather than treating it as evidence that I cannot do the work;
- produce a real compiler one trustworthy layer at a time.

The project succeeds when I can explain and defend what I built. A feature that appears to work but that I cannot explain is not finished learning.

## 2. The working promise

> I am not trying to one-shot perfect code from my mind. I am becoming the programmer who can build difficult systems by making, testing, explaining, and repairing small things.

Progress is iterative:

1. predict what should happen;
2. implement the smallest useful step;
3. run it;
4. study the disagreement between the prediction and reality;
5. fix one cause;
6. record the lesson;
7. repeat.

Speed is a result of accumulated understanding. It is not a requirement at the beginning.

## 3. Product direction

Kō is intended to become a small language and compiler whose behaviour is understandable from end to end. The current language documents describe a compact imperative and expression-oriented frontend with explicit declarations, structured control flow, pattern matching, pipes, errors and optionals.

That direction is useful, but it is not the current deliverable. The current product is the next trustworthy compiler boundary.

The pipeline will grow in this order:

```text
source text
  -> tokens
  -> syntax tree
  -> names and types
  -> a simple intermediate representation
  -> execution or native code
```

Every boundary must have:

- a written contract;
- a small implementation;
- examples and counterexamples;
- tests that genuinely execute it;
- a short explanation in my own words.

## 4. Principles

### 4.1 Learning is part of the definition of done

Each milestone must produce both working software and evidence of understanding. I should be able to reconstruct the important reasoning without copying the source.

### 4.2 Working vertical slices beat broad unfinished design

A small tokenizer that always advances, returns correct spans, and is tested is more valuable than a broad frontend in which every stage is partially implemented.

### 4.3 The specification and implementation may evolve together

The language documents are hypotheses until implementation and tests pressure-test them. When code and documentation disagree, I must decide deliberately which one is wrong and record the decision.

### 4.4 Failure must be cheap and informative

Prefer tiny experiments, focused tests and short feedback loops. A failed ten-minute experiment is useful. A week of changes that cannot be isolated is expensive.

### 4.5 One active problem at a time

During a session, new ideas go into the parking lot. They do not replace the selected task unless they prove that the task itself is invalid.

### 4.6 AI supports judgment; it does not replace authorship

All Kō implementation code is written by me. AI may explain Zig semantics, question an invariant, review code I wrote, help locate documentation, propose test categories, or challenge my reasoning. I do not accept an AI-generated implementation that I cannot independently derive and explain.

## 5. Verified starting point — 18 October 2026

The local checkout and `origin/main` both point to commit `be4b8e7` (`init: intial docs and wip tokenizer`). The checkout contains one uncommitted edit in `src/tokenizer.zig`; it completes part of the unfinished `|` branch. That edit is preserved as work in progress.

The current toolchain is Zig 0.17.0. The package declares Zig 0.16.0 as its minimum version, but the generated build script uses an API that no longer exists in the installed toolchain:

```text
build.zig:114:11: error: no field named 'args' in struct 'Build'
```

The current validation results are:

- `zig build test` fails in `build.zig` before project tests run;
- `zig test src/tokenizer.zig` succeeds while reporting **0 tests**, so it does not validate `Tokenizer.next()`;
- `zig run src/main.zig` reaches the tokenizer and fails on the invalid range `'a'...'Z'`;
- `src/root.zig` contains only the template arithmetic test;
- the tokenizer declares a broad vocabulary, but recognition is incomplete;
- the language contract and the lexer decision record contain useful direction, but some described representation choices do not match the current code.

This is not a failure of the project. It is the first honest baseline.

## 6. Current milestone — M1: a reliable tokenizer boundary

### 6.1 Outcome

By the end of this milestone, Kō must reliably tokenize:

- empty input and end of file;
- ASCII whitespace by skipping it without emitting tokens;
- identifiers;
- every currently declared keyword and reserved word;
- the explicit M1 punctuation inventory below;
- the explicit M1 operator inventory below, including shared prefixes;
- invalid bytes without hanging or reading beyond the source.

Every returned token must have a correct half-open byte span `[start, end)`.

### 6.2 M1 input and token contract

M1 accepts a sentinel-terminated source buffer, `[:0]const u8`. The sentinel at `buffer[buffer.len]` marks the end of the source and is not itself a source byte.

Within M1:

- identifiers are ASCII and follow `[A-Za-z_][A-Za-z0-9_]*`;
- space, tab, carriage return and newline are skipped;
- newline does **not** produce `TERM` yet;
- an embedded NUL before `buffer.len` is one invalid byte, not EOF;
- bytes outside the accepted ASCII token vocabulary are one-byte invalid tokens;
- an invalid token has the span of the byte that caused it, allowing scanning to continue.

Keywords and reserved words:

```text
import struct enum func let mut defer return break continue
if else while match try or as true false many
for in pub const union type
```

Punctuation in M1:

```text
( ) { } [ ] , : . # ?
```

Semicolon and newline-to-`TERM` behaviour are deliberately deferred to M2.

Canonical operator inventory:

| Lexeme | Token | Shared-prefix obligation |
|---|---|---|
| `!` | `bang` | prefer `!=` when present |
| `!=` | `bang_equal` | — |
| `|` | `pipe` | prefer `||` or `|>` when present |
| `||` | `pipe_pipe` | — |
| `|>` | `pipe_angle_bracket_right` | — |
| `&&` | `ampersand_ampersand` | a lone `&` is invalid |
| `=` | `equal` | prefer `==` or `=>` when present |
| `==` | `equal_equal` | — |
| `=>` | `equal_angle_bracket_right` | — |
| `+` | `plus` | prefer `+=` when present |
| `+=` | `plus_equal` | — |
| `-` | `minus` | prefer `-=` when present |
| `-=` | `minus_equal` | — |
| `*` | `asterisk` | prefer `*=` when present |
| `*=` | `asterisk_equal` | — |
| `/` | `slash` | prefer `/=` when present |
| `/=` | `slash_equal` | — |
| `%` | `percent` | — |
| `<` | `angle_bracket_left` | prefer `<=` when present |
| `<=` | `angle_bracket_left_equal` | — |
| `>` | `angle_bracket_right` | prefer `>=` when present |
| `>=` | `angle_bracket_right_equal` | — |

### 6.3 Why this milestone comes first

The parser cannot be trustworthy while token boundaries are unstable. More importantly, the current repository does not yet have a truthful build-and-test loop. Restoring that loop teaches essential Zig skills while making every later compiler stage easier to learn.

### 6.4 Explicit non-goals

Do not begin the AST, parser, diagnostic renderer, type system, ownership system, LLVM integration, package manager or standard library during this milestone.

Do not expand the language syntax.

Numeric prefixes, separators, exponents, strings, characters, comments, semicolons and newline-to-`TERM` insertion belong to M2. Existing incomplete branches may remain isolated or be made safely invalid, but they are not allowed to destabilize M1.

Do not redesign the token representation unless a failing test demonstrates that the current representation blocks the milestone.

### 6.5 Tokenizer invariants

The implementation and tests must establish these properties:

1. Every non-EOF token consumes at least one byte.
2. Repeated calls eventually return EOF.
3. EOF has the span `[source.len, source.len)`.
4. Every ordinary token has `start < end <= source.len`.
5. The tokenizer never reads beyond the sentinel-terminated buffer.
6. Finishing one token does not consume the first byte of the next token.
7. Invalid input still guarantees progress.
8. Keywords match only complete identifier lexemes: `match` is a keyword and `matcher` is an identifier.
9. Every shared prefix in the canonical operator inventory uses maximal munch, including `!=`, the four compound assignments, `||`, `|>`, `==`, `=>`, `<=`, and `>=`.
10. Tests exercise `Tokenizer.next()` rather than merely compiling the file that contains it.

### 6.6 Definition of done

M1 is complete only when all of the following are true:

- [ ] The project names and pins or documents one supported Zig version for the milestone.
- [ ] `zig build` succeeds.
- [ ] `zig build run` terminates and prints or otherwise exposes a finite token stream.
- [ ] `zig build test` succeeds and visibly executes tokenizer tests.
- [ ] A coverage matrix has at least one passing row for every M1 keyword, reserved word, punctuation token and operator, plus identifier near misses and invalid-input classes.
- [ ] All identifiers, current keywords, M1 punctuation and M1 operators have tested recognition paths.
- [ ] Maximal munch is tested for every shared operator prefix.
- [ ] Empty input, trailing whitespace, every single-byte value and a deterministic set of short generated inputs terminate within a test-imposed token bound under Zig's safety checks.
- [ ] Token spans are asserted, not only token tags.
- [ ] The lexer contract and implementation no longer contradict each other within M1 scope.
- [ ] The existing uncommitted tokenizer work has been deliberately completed, revised or discarded rather than accidentally overwritten.
- [ ] I can pass the comprehension check without looking at the implementation.

## 7. Seven-session execution plan

Each session is two hours. The task may finish early; do not enlarge it merely to fill the block.

The session numbers describe dependency order, not permission to advance because the date changed. If a session does not produce its exit evidence, it remains the next session. Everything after it slides. Never start a dependent slice on an unverified foundation.

The Sunday review still happens on 25 October even if M1 remains open. At that review, record the blocker, slide the unfinished session, and update the target window rather than weakening the definition of done.

Create a small checkpoint commit after each coherent slice whose focused tests pass. Session 7 closes the milestone; it is not the first time the week's work should be committed.

### Session 1 — Restore the build feedback loop

**Question:** How does this Zig version pass executable arguments through the build graph, and which project modules does each test artifact compile?

**Work:**

- read the failing part of `build.zig` and the relevant Zig 0.17 build API;
- make the smallest hand-written change required for the build graph to load;
- run `zig build`, `zig build run` and `zig build test` separately;
- record which command reaches which source module.

**Exit evidence:** The build script loads on Zig 0.17, and any remaining failure comes from project code rather than the build API. The exact first project-code compile blocker is recorded for Session 2.

### Session 2 — Make tests truthful

**Question:** Why can a Zig file report zero passing tests even though an uncompiled function body contains an error?

**Work:**

- if `Tokenizer.next()` still cannot compile, repair only the recorded minimum compile blocker before testing behaviour; do not expand token coverage yet;
- add the smallest tokenizer test that calls `Tokenizer.next()`;
- prove that an intentionally wrong expectation fails;
- prove that correcting the expectation passes;
- confirm `zig build test` discovers the tokenizer test.

**Exit evidence:** The test command can fail for tokenizer behaviour and pass after a deliberate correction.

### Session 3 — Establish EOF, whitespace and progress

**Question:** What exact state change guarantees that every non-EOF call advances?

**Work:**

- test empty input, whitespace-only input and trailing whitespace;
- verify the declared embedded-NUL rule separately from the sentinel;
- make invalid input consume exactly one byte;
- use a bounded test driver that permits at most `source.len + 1` calls to `next()`, including the final EOF call;
- test every possible single byte from `0x00` through `0xff`;
- generate every input of length zero through three over this fixed alphabet: `0x00`, `0x01`, `0x7f`, `0x80`, `0xff`, space, newline, `a`, `Z`, `_`, `0`, `!`, `|`, `&`, `=`, `+`, `-`, `*`, `/`, `%`, `<`, `>`;
- for focused EOF, whitespace and invalid cases, assert exact tags, spans and the final tokenizer position;
- for the generated corpus, assert only termination, monotonic progress, span bounds and final EOF; Sessions 4–6 add exact recognition expectations for identifiers and operators.

**Exit evidence:** Repeated calls terminate at EOF for the declared M1 input checks without exceeding the test bound or triggering a safety failure.

### Session 4 — Complete identifiers and keywords

**Question:** Why is `[A-Za-z_][A-Za-z0-9_]*` different from the invalid character range currently written in the source?

**Work:**

- implement the identifier start and continuation contract;
- verify every keyword and reserved word through table-driven cases;
- test near misses such as `match`, `matcher`, `let123`, `_name` and `name_2`;
- assert exact byte spans.

**Exit evidence:** Identifier and keyword tests pass without special cases leaking into the parser.

### Session 5 — Implement punctuation and the unambiguous `%` operator

**Question:** Which tokens can be decided from one byte, and why do they not need persistent DFA states?

**Work:**

- cover the explicit M1 punctuation inventory and `%`, the only M1 operator with no longer shared-prefix form;
- keep recognition direct and readable;
- test adjacent tokens with no whitespace.

**Exit evidence:** Every M1 punctuation token and `%` are recognized with the correct span.

### Session 6 — Implement shared prefixes with bounded lookahead

**Question:** How does the tokenizer choose the longest valid token without consuming the next token?

**Work:**

- complete every remaining row in the canonical operator inventory, including the one-byte base tokens whose paths require lookahead;
- test EOF immediately after each prefix;
- test compact adversarial streams such as `a|||>b`, `==>`, `&x` and `foo+bar`.

**Exit evidence:** Maximal-munch cases and boundary cases pass.

### Session 7 — Validate, explain and close

**Question:** Can I explain the tokenizer as a contract rather than reciting its code?

**Work:**

- open a fresh terminal using the documented Zig executable and version, then run the full build and test commands;
- inspect the test output and confirm tokenizer cases actually ran;
- reconcile the M1 parts of `LANGUAGE.md`, `GRAMMAR.md` and `DECISONS.md` with the implementation;
- write the three hardest lessons and the exact next milestone boundary;
- create the milestone-closing commit only after the evidence is reproducible.

**Exit evidence:** Every definition-of-done item is checked honestly, or the milestone remains open with one named blocker.

## 8. The two-hour session protocol

Use the same structure every morning so starting does not require a fresh planning decision.

| Time | Activity |
|---|---|
| 05:00–05:10 | Read the session question and write one predicted outcome. |
| 05:10–05:25 | Read only the documentation or nearby code needed for this slice. |
| 05:25–06:25 | Implement the smallest useful change by hand. |
| 06:25–06:45 | Run focused tests, investigate the first disagreement and revise. |
| 06:45–06:55 | Run the broader relevant command. |
| 06:55–07:00 | Record what changed, what failed, what I learned and the first action for tomorrow. |

The end-of-session log should fit in four lines:

```text
Changed:
Observed:
Learned:
Next:
```

## 9. Failure protocol

When something fails:

1. stop changing unrelated code;
2. copy the exact first error or failing assertion into the session notes;
3. state what I expected instead;
4. reduce the input or command until the disagreement is small;
5. explain the relevant state, value or type in my own words;
6. make one minimal change;
7. run the same reproduction again;
8. only then run the broader suite.

If I am stuck for 30 minutes, I may ask for help. The request should include the prediction, actual result, smallest reproduction and my current explanation. Ask first for a hint or semantic explanation, not a completed implementation.

On a low-energy day, the minimum useful session is:

- one focused failing test or reproduction;
- one written explanation of the failure;
- one clearly named next action.

That preserves continuity without pretending that unfinished work is complete.

## 10. Decision discipline

Record a decision when it changes a contract, closes off a meaningful alternative, or will matter to a later compiler stage. Do not record ordinary syntax corrections as architecture.

Every decision should state:

- the problem;
- the options considered;
- the chosen rule;
- the reason;
- what evidence could cause the rule to change.

During M1, record and validate the already declared embedded-NUL and one-byte invalid-span rules. The main unresolved implementation decision is direct lookahead versus explicit states for short operators; the chosen structure must preserve the same token contract.

## 11. Comprehension check — the Griot test

Without opening the source, I must be able to explain:

1. why `Tokenizer.next(self: *Tokenizer)` requires a mutable tokenizer value;
2. why `zig test src/tokenizer.zig` can report zero tests without compiling every function body;
3. the difference between an identifier-start byte and an identifier-continuation byte;
4. why `matcher` must not become `keyword_match` followed by `er`;
5. why `a|||>b` has the token boundaries it does under maximal munch;
6. how accepting one token preserves the first byte of the next token;
7. why EOF and invalid input require different spans but the same progress discipline;
8. which tests prove the tokenizer is safe rather than merely plausible.

If I cannot explain one of these, I have found the next learning task. That discovery is useful, but the unchecked explanation keeps M1 open until I can resolve it.

## 12. Direction after M1

Later milestones are directional until the current milestone closes.

### M2 — Complete the lexical contract

Numbers, strings, characters, comments, escapes, semicolons and deterministic newline-to-`TERM` insertion. Resolve stale token-representation decisions against measured implementation needs.

### M3 — Build an inspectable AST

Derive node vocabulary from the grammar, choose an arena representation, keep spans inspectable, and construct nodes manually in tests before writing the parser.

### M4 — Parse expressions and declarations

Build a small Pratt parser and recursive-descent statement/declaration parser. Start from adversarial inputs and explicit diagnostics rather than only valid examples.

### M5 — Resolve names and check simple types

Introduce scopes, symbols and a deliberately small type-checking boundary. Prefer explainable errors over language breadth.

### M6 — Execute one vertical slice

Choose the smallest interpreter or lowering path that can run a tiny Kō program end to end. Native code generation is earned by stable earlier representations; it is not required to prove that the frontend is real.

## 13. Weekly review questions

At the Sunday review, answer:

- What can the repository demonstrably do now that it could not do last week?
- Which test or failure taught me the most?
- Which part can I explain without looking at the code?
- Where did I redesign instead of finish?
- What should be removed or postponed?
- What is the next smallest boundary that produces visible evidence?

The next week receives one milestone, not a list of every interesting compiler problem.
