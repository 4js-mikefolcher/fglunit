# Spec 0001 — Test discovery & multi-suite aggregation

Status: **Implemented** (approved 2026-06-04)
Author: fglunit maintainers
Date: 2026-06-04
Closes: gap #1 (no test discovery / aggregation across files)

## 1. Problem

fglunit today requires two things that mature frameworks (JUnit, pytest, Jest)
do not:

1. **Manual registration.** Every test needs a hand-written
   `CALL FglUnit.register("name", FUNCTION name)` line in a `MAIN`. BDL has no
   reflection over functions, so the names can't be enumerated at runtime.
2. **One program == one suite.** Each test program is a standalone `MAIN` that
   prints its own report and returns its own exit code. There is no way to run a
   directory of test programs and get **one** aggregated report / exit code,
   which is the baseline "run my test suite" experience everywhere else.

This spec closes both halves with two new pure-BDL tools, leaving the existing
runtime API and the hand-written style fully backward compatible.

## 2. Approach (decided)

- **Discovery → a BDL code generator.** A pure-BDL tool scans test source
  modules for `PUBLIC FUNCTION test*` (plus fixtures by convention) and emits a
  generated runner module per test module. Stays "pure BDL"; the only new build
  artifact is a generated `.4gl`.
- **Aggregation → a BDL subprocess driver.** A pure-BDL program runs each
  compiled test program as a child process, has each emit JUnit XML to a temp
  file, then merges those into one `<testsuites>` report with a combined console
  summary and a combined exit code.

### Why subprocess driver over a single aggregate process

- **Isolation.** A suite that abends (uncaught fatal, `EXIT PROGRAM`, segfault
  in a C extension) cannot take down the other suites or the aggregate report.
- **No core rewrite.** The runtime stays single-suite (`one suiteName`, one
  `registry`). Multi-suite lives entirely in the driver.
- **Matches today's model.** Each test program already is a self-contained
  process that emits JUnit XML; the driver just orchestrates and merges.

Trade-off accepted: process-spawn cost per suite, and results are exchanged via
temp JUnit files rather than shared memory.

## 3. Validated assumptions (compile-probed)

- A plain module (no `PACKAGE`) with `PUBLIC FUNCTION test_*` compiles with
  `fglcomp -M` and needs no `MAIN`.
- A separate module can `IMPORT FGL <that module>` and take a cross-module
  function pointer — `LET h = FUNCTION test_mod.test_one` — and call it. This is
  the mechanic the generated runner relies on.
- `IMPORT FGL <mod>` requires the imported module to **not** contain a `PACKAGE`
  declaration. (User test modules must therefore be plain modules — see §4.1.)
- Available runtime APIs confirmed in the local SDK: `base.Channel.openPipe`,
  `RUN ... RETURNING <status>`, `os.Path.*` (exists/isDirectory/baseName/
  dirName/join), `xml.DomDocument`, `base.Application.*`.

To confirm during implementation: passing `FUNCTION test_mod.test_one` *directly*
as a `register(name, FglUnit.TestHandler)` argument (probe validated assignment
to a local var of identical signature; direct-arg is expected to behave the same
since same-module direct-arg already works today).

## 4. Part A — Discovery code generator

### 4.1 Test module convention (the input)

A **test module** is a plain `.4gl` (no `PACKAGE`, no `MAIN`). By convention the
filename starts with `test_` but discovery keys off function names, not the
filename. It contains:

| Symbol (must be `PUBLIC`) | Role |
|---|---|
| `FUNCTION test*()` `RETURNS ()` | a test case (one per function) |
| `FUNCTION setUp()` | per-test setup (optional) |
| `FUNCTION tearDown()` | per-test teardown (optional) |
| `FUNCTION setUpSuite()` | once-before-all (optional) |
| `FUNCTION tearDownSuite()` | once-after-all (optional) |

Fixtures **must be `PUBLIC`** so the generated runner can take pointers to them.
Test functions are already `PUBLIC` today.

Example `test_Calculator.4gl` (note: no `MAIN`, imports its own deps):

```4gl
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL Calculator

PUBLIC FUNCTION setUp()
    -- per-test setup
END FUNCTION

PUBLIC FUNCTION test_add_two_positives()
    CALL Assertions.assertEqualsInt(5, Calculator.add(2, 3), "2 + 3")
END FUNCTION

PUBLIC FUNCTION test_sub_basic()
    CALL Assertions.assertEqualsInt(7, Calculator.sub(10, 3), "10 - 3")
END FUNCTION
```

### 4.2 Parsing rules

A lightweight line scanner (not a full BDL parser), using `util.Regexp`:

- Match, case-insensitively, lines of the form
  `^\s*PUBLIC\s+FUNCTION\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(`.
- A name matching `^test` (case-insensitive) → a **test case**.
- A name exactly equal (case-insensitive) to `setUp` / `tearDown` /
  `setUpSuite` / `tearDownSuite` → the corresponding **fixture**.
- Order of test cases = source order (line number ascending).
- **Skip comments:** ignore content after `#` / `--` line comments and inside
  `{ ... }` block comments. (Documented limitation: a `PUBLIC FUNCTION test*`
  buried inside a block comment that also opens mid-line in an exotic way may be
  mis-scanned. Acceptable for v1; the scanner handles the common cases.)
- Duplicate test names, or more than one of a given fixture, → hard error
  (non-zero exit, clear message). Ambiguity must fail loudly, not silently pick.

The parser is a **pure function** over the source text (string in → struct out)
so it can be unit-tested with fglunit itself (see §6).

### 4.3 Generated runner (the output)

For input `test_Calculator.4gl`, generate `test_Calculator.run.4gl`:

```4gl
-- GENERATED by fglunit-gen — DO NOT EDIT.
-- source:    test_Calculator.4gl
-- generator: com.fourjs.fglunit v<version>
IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL test_Calculator

MAIN
    CALL CliArgs.parse()
    CALL FglUnit.suite("Calculator")
    CALL FglUnit.setSetup(FUNCTION test_Calculator.setUp)            -- emitted only if present
    CALL FglUnit.setTeardown(FUNCTION test_Calculator.tearDown)      -- emitted only if present
    CALL FglUnit.register("test_add_two_positives", FUNCTION test_Calculator.test_add_two_positives)
    CALL FglUnit.register("test_sub_basic",         FUNCTION test_Calculator.test_sub_basic)
    EXIT PROGRAM FglUnit.run()
END MAIN
```

- Suite name defaults to the source basename with a leading `test_`/`test`
  stripped (`test_Calculator` → `Calculator`); overridable via `--suite`.
- The generated file carries a `DO NOT EDIT` header and is safe to `.gitignore`
  or to check in — caller's choice.
- Generating for a module that has **zero** `test*` functions → warning + no
  file written (non-fatal), so directory sweeps don't choke on helpers.

### 4.4 Generator CLI

Entry: `bin/fglunit_gen.4gl` (plain module, `MAIN`) → `fglunit_gen.42m`.

```
fglrun fglunit_gen.42m [options] <test-source.4gl> ...
  --dir <d>        discover test_*.4gl under <d> (non-recursive in v1)
  --out <file>     output path (single input only; default <base>.run.4gl)
  --suite <name>   override suite name (single input only)
  --stdout         write to stdout instead of a file
  -h, --help
```

- Multiple inputs (or `--dir`): one `<base>.run.4gl` written next to each source.
- Exit 0 on success, non-zero on any parse/duplicate error.

## 5. Part B — Subprocess aggregation driver

### 5.1 Behaviour

Entry: `bin/fglunit_run.4gl` (plain module, `MAIN`) → `fglunit_run.42m`.

```
fglrun fglunit_run.42m [options] <program.42m> ...
  --dir <d>        run every *.run.42m under <d> (non-recursive in v1)
  --junit <file>   write aggregated <testsuites> XML
  --filter <pat>   passed through to each child suite
  --fail-fast      stop after the first failing suite
  -v, --verbose    passed through to each child suite
  --color <mode>   auto | always | never (driver + children)
  -h, --help
```

For each child program, in order:

1. Allocate a temp JUnit path (under `$TMPDIR`/`os.Path` temp; unique per child).
2. Run `fglrun <prog> --junit <tmp> --color never [--filter ..] [-v]` as a child
   process via `base.Channel.openPipe` (capture console for `-v` pass-through) or
   `RUN ... RETURNING st` (capture exit status). Capture **both** console and
   exit status.
3. Read & parse the temp JUnit XML with `xml.DomDocument`.
4. Stream a one-line progress summary for the suite
   (`Calculator … 8 tests, 0 failed (12 ms)`).
5. If `--fail-fast` and the suite failed (non-zero exit **or** failures/errors in
   XML), stop and skip the rest.

After all children:

- Print a combined summary:
  `Suites: S  Tests: N  Passed: P  Failed: F  Errors: E  Skipped: K  Time: T ms`.
- If `--junit`, write a `<testsuites …>` document wrapping each child
  `<testsuite>` (totals summed across children). Built by re-serializing the
  parsed DOM nodes, so escaping is handled by `xml.DomDocument` — no manual
  escaping needed in the aggregator.
- Exit code: `0` iff **every** child exited `0` and no merged failures/errors;
  `1` otherwise.

### 5.2 Robustness — degenerate children

The driver must not trust children. Each is classified:

| Child outcome | Driver behaviour |
|---|---|
| Exit 0/1, valid JUnit written | Merge normally |
| Non-zero exit, **no/empty/invalid** XML (crash/abend) | Synthesize a `<testsuite>` with one `<error>` testcase ("suite crashed: exit N", plus captured stderr tail). Counts as an error; fails the build |
| Program not found / not executable | Hard driver error before the run loop |

This is the key value of the subprocess model: a crashing suite is *reported*,
not silently dropped.

### 5.3 Aggregated XML shape

```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuites tests="N" failures="F" errors="E" skipped="K" time="T">
  <testsuite name="Calculator" tests="8" failures="0" errors="0" skipped="0" time="0.012"> ... </testsuite>
  <testsuite name="Strings"    tests="5" failures="1" errors="0" skipped="0" time="0.004"> ... </testsuite>
</testsuites>
```

Consumed natively by Jenkins/GitLab/GitHub test reporters (they already expect
a `<testsuites>` root for multi-suite).

## 6. New / changed files

```
com/fourjs/fglunit/Discovery.4gl    NEW  parse source -> discovered symbols; render runner text (pure, testable)
com/fourjs/fglunit/Aggregator.4gl   NEW  read N child JUnit files -> merged <testsuites> (pure-ish, testable)
bin/fglunit_gen.4gl                 NEW  MAIN: generator CLI (thin wrapper over Discovery)
bin/fglunit_run.4gl                 NEW  MAIN: subprocess driver CLI (uses Aggregator)
tests/test_Discovery.4gl            NEW  unit tests for the parser + renderer
tests/test_Aggregator.4gl           NEW  unit tests for the merge logic
Makefile                            EDIT add build targets for bin/* ; add a `gen`/`suite` demo target
tests/Makefile                      EDIT compile + run the two new self-test modules
examples/                           EDIT add a discovery-style example (test module + generated runner + driver run)
README.md / USERGUIDE.md            EDIT document discovery, the driver, and the new conventions
```

- **No changes to** `FglUnit.4gl`, `Assertions.4gl`, `CliArgs.4gl`. The runtime
  contract is untouched; both tools build on the existing public API and the
  existing per-suite JUnit output.
- `Reporter.4gl`: unchanged for v1. The aggregator does its own `<testsuites>`
  serialization via DOM rather than reusing Reporter's private `xmlEscape`. (If
  we later want shared helpers, extract them then — not now.)

## 7. Dogfooding / test plan

The framework tests itself — the strongest possible demonstration.

- **`tests/test_Discovery.4gl`**: feed the parser representative source strings;
  assert discovered test names + order, fixture detection, comment skipping,
  duplicate-name error, and exact generated-runner text for a known input.
- **`tests/test_Aggregator.4gl`**: feed sample child JUnit strings; assert summed
  totals, the `<testsuites>` shape, and the crashed-child synthesis path.
- **End-to-end (Make):** convert `examples/test_Calculator` to the new
  no-`MAIN` convention, generate its runner with `fglunit_gen`, compile, then run
  the whole `examples/` + `tests/` set through `fglunit_run` and assert a green
  aggregate with exit 0. A deliberately-failing fixture is added under a
  temporary target to prove non-zero exit + crashed-child reporting.
- Existing self-tests (`tests/test_Assertions.4gl`) keep running in their current
  hand-written form — proving backward compatibility.

## 8. Acceptance criteria

1. `fglunit_gen` turns a no-`MAIN` test module into a compilable runner that,
   when built and run, produces identical output to the equivalent hand-written
   `MAIN` (verified against the converted Calculator example).
2. Fixtures (`setUp`/`tearDown`/`setUpSuite`/`tearDownSuite`) are auto-wired only
   when present.
3. Duplicate test names / duplicate fixtures fail generation with a clear,
   non-zero error.
4. `fglunit_run` runs ≥2 compiled suites and emits one console summary + one
   `<testsuites>` XML with correctly summed totals.
5. A crashing child suite is reported as an error in the aggregate and forces a
   non-zero driver exit (it is never silently dropped).
6. Aggregate exit code is 0 iff all suites pass; 1 otherwise.
7. `--filter`, `-v`, `--color`, `--fail-fast` behave as documented.
8. The existing hand-written registration style still compiles and runs
   unchanged (backward compatible).
9. `make test` is green, including the two new self-test modules.

## 9. Out of scope (explicit)

- Recursive directory discovery (v1 is non-recursive; note it).
- Parallel execution of child suites (still sequential — separate gap).
- Watch mode, coverage, tags/markers (separate gaps).
- Replacing the hand-written style — it remains a first-class, supported option.
- Sharing/refactoring `Reporter`'s private XML helpers.

## 10. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Cross-module function pointer passed *directly* to `register()` rejected by compiler | Probe validated the assignment form; if direct-arg fails, the generator emits `DEFINE h FglUnit.TestHandler; LET h = FUNCTION mod.fn; CALL FglUnit.register(..., h)` instead — fully equivalent |
| Line-scanner mis-parses exotic formatting (block comments, multi-line signatures) | Document the supported subset; fail loud on ambiguity; full parser is a future option |
| Temp-file location / cleanup across OSes | Use `os.Path` temp conventions; unique names per child; clean up on exit, leave on crash for debugging |
| `openPipe` vs `RUN` can't give both console *and* exit status cleanly | Drive children with `--junit` as the source of truth for results; use exit status only to detect crash/abend; capture console via `openPipe` for `-v` |
| Child suite writes no XML on `--list` or `--help` paths | Driver only ever invokes children in run mode; never forwards `--list`/`--help` |

## 11. Rollout

1. Land `Discovery.4gl` + `test_Discovery.4gl` (generator core, dogfooded).
2. Land `bin/fglunit_gen.4gl` + Make wiring + convert the Calculator example.
3. Land `Aggregator.4gl` + `test_Aggregator.4gl`.
4. Land `bin/fglunit_run.4gl` + end-to-end Make target.
5. Docs (README/USERGUIDE): new "Discovery & running a whole suite" section;
   update the Limitations list.

Each step is independently green, so review can happen incrementally.

## 12. Addendum — packaging & OS-agnosticism (post-approval)

Two requirements surfaced during implementation:

1. **Ship the tools as runnable programs.** The two CLIs live under the
   package root (`com/fourjs/fglunit/fglunit_gen.4gl` /
   `fglunit_run.4gl`, each `PACKAGE com.fourjs.fglunit` + `MAIN` so they
   self-place on compile) and are declared in `fglpkg.json` `programs`.
   After `fglpkg install fglunit` they run via
   `fglpkg bdl fglunit fglunit_gen|fglunit_run`. `fglpkg bdl` sets the
   working directory to the installed-package dir, so paths passed under
   `bdl` must be absolute; direct `fglrun` keeps normal cwd-relative paths.

2. **OS-agnostic — no Unix-isms.** The driver launches children with
   portable primitives only: `fgl_setenv("FGLLDPATH", …)` (child inherits;
   no `VAR=val cmd` prefix), `os.Path.pathSeparator()` for the list
   separator, `base.Channel.openPipe(… , "r")` for output capture (no `>` /
   temp log), `TMPDIR`/`TEMP`/`TMP` probing for the temp dir (no hard-coded
   `/tmp`), and crash detection via the absence of valid JUnit (no Unix
   `wait()`-status decoding). No reliance on `$PWD`.
