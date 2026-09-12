# fglunit — User Guide

xUnit-style unit testing for Genero BDL. Pure BDL — no GGC server, no
shell tooling, no codegen.

## Contents

1. [Requirements](#requirements)
2. [Install](#install)
3. [Writing your first test](#writing-your-first-test)
4. [Assertions](#assertions)
5. [Fixtures: setUp / tearDown](#fixtures-setup--teardown)
6. [Suite-level setUp / tearDown](#suite-level-setup--teardown)
7. [Testing error paths (`assertThrows` and `WHENEVER ANY ERROR RAISE`)](#testing-error-paths)
8. [Skipping tests](#skipping-tests)
9. [Running tests](#running-tests)
10. [Discovery & running a whole test tree](#discovery--running-a-whole-test-tree)
11. [JUnit XML for CI](#junit-xml-for-ci)
12. [Failure vs Error](#failure-vs-error)
13. [When to use fglunit vs GGC](#when-to-use-fglunit-vs-ggc)
14. [Limitations](#limitations)

---

## Requirements

Genero BDL **4.00 or newer**. `fglunit` uses `util.Regexp` (behind
`assertMatches`) and `STRING.replaceAll` (JUnit XML escaping), both
introduced in BDL 4.00.

## Install

```bash
fglpkg install fglunit
eval "$(fglpkg env --local)"
```

Each test program imports the modules it needs:

```4gl
IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs    -- optional; needed only if
                                          -- you want CLI flag parsing
```

## Writing your first test

A test program is just a regular `.4gl` module with a `MAIN` that
registers test functions and calls `FglUnit.run()`. Each test is a
`PUBLIC FUNCTION` with no parameters and no return value.

> **`MAIN` goes first.** BDL requires the `MAIN` block to precede every
> `FUNCTION` in the module (module-level `DEFINE`s may come before it).
> Putting `MAIN` at the bottom fails to compile with
> `error:(-6609) A grammatical error has been found at 'MAIN'`.

```4gl
IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs

MAIN
    CALL CliArgs.parse()               -- enables --junit, --filter, -v, ...
    CALL FglUnit.suite("basic math")
    CALL FglUnit.register("test_addition",        FUNCTION test_addition)
    CALL FglUnit.register("test_string_contains", FUNCTION test_string_contains)
    EXIT PROGRAM FglUnit.run()
END MAIN

PUBLIC FUNCTION test_addition()
    CALL Assertions.assertEqualsInt(4, 2 + 2, "2 + 2 should equal 4")
END FUNCTION

PUBLIC FUNCTION test_string_contains()
    CALL Assertions.assertContains("hello world", "world", "substring match")
END FUNCTION
```

`CliArgs.parse()` is optional, but without it the program ignores every
command-line flag in [Running tests](#running-tests).

Compile and run:

```bash
fglcomp -M my_tests.4gl
fglrun my_tests.42m
```

```
basic math
  v test_addition
  v test_string_contains

Tests: 2  Passed: 2  Failed: 0  Errors: 0  Skipped: 0  Time: 1 ms
```

> **Why explicit registration?** BDL has no reflection over functions —
> there is no way to enumerate `test_*` symbols at runtime. Registering
> by hand keeps the framework predictable, dependency-free, and free of
> codegen build steps. One line per test is a cheap price for zero magic.

## Assertions

All assertions take a `msg STRING` last parameter that's surfaced when
they fail. When an assertion fails, the test continues running — the
**first** failure is reported (JUnit semantics). Use `assertThrows` to
stop early or just structure your tests with one logical check each.

| Assertion | Notes |
|---|---|
| `assertTrue(cond, msg)` | `cond` is `BOOLEAN` |
| `assertFalse(cond, msg)` | |
| `assertEquals(expected, actual, msg)` | string equality, NULL-aware |
| `assertNotEquals(a, b, msg)` | |
| `assertEqualsInt(expected, actual, msg)` | `INTEGER` |
| `assertEqualsDec(expected, actual, tolerance, msg)` | `DECIMAL(32,10)` with absolute tolerance |
| `assertNull(value, msg)` | |
| `assertNotNull(value, msg)` | |
| `assertContains(haystack, needle, msg)` | substring match |
| `assertNotContains(haystack, needle, msg)` | |
| `assertMatches(value, regex, msg)` | `util.Regexp` POSIX regex |
| `assertThrows(fn, msg)` | passes if `fn()` raises (see below) |
| `fail(msg)` | unconditional failure |
| `skip(msg)` | mark current test as skipped |

## Fixtures: setUp / tearDown

`setUp` runs before each test, `tearDown` after. Both are optional and
take a `TestHandler` (parameterless function reference).

```4gl
PRIVATE DEFINE counter INTEGER

MAIN
    CALL FglUnit.setSetup(FUNCTION reset_counter)
    CALL FglUnit.register("test_increment", FUNCTION test_increment)
    EXIT PROGRAM FglUnit.run()
END MAIN

PRIVATE FUNCTION reset_counter()
    LET counter = 0
END FUNCTION

PUBLIC FUNCTION test_increment()
    LET counter = counter + 1
    CALL Assertions.assertEqualsInt(1, counter, "first call sets to 1")
END FUNCTION
```

If `setUp` raises an error, the test is marked **ERROR** and the body
does not run. If the test body raises, `tearDown` does **not** run for
that test (matches JUnit; isolate teardown by wrapping in TRY/CATCH if
you need it to run unconditionally).

## Suite-level setUp / tearDown

`setSetupSuite` runs once before the first test, `setTeardownSuite`
once after the last. Useful for opening a DB connection or seeding
fixture data.

```4gl
CALL FglUnit.setSetupSuite(FUNCTION connect_test_db)
CALL FglUnit.setTeardownSuite(FUNCTION drop_test_db)
```

## Testing error paths

`assertThrows(fn, msg)` passes if `fn()` raises a runtime error.

**Important — BDL error propagation.** BDL's `TRY/CATCH` only catches
errors that the called function lets *propagate*. By default, expression
errors (division by zero, NULL dereference, etc.) inside a called
function are **silently absorbed**. To make them propagate, every
function on the call path between the failing operation and
`assertThrows`'s `TRY/CATCH` must declare:

```4gl
WHENEVER ANY ERROR RAISE
```

This is the standard BDL idiom for surfaceable errors. Example:

```4gl
# code under test
PUBLIC FUNCTION divide(a INTEGER, b INTEGER) RETURNS INTEGER
    WHENEVER ANY ERROR RAISE        -- propagate to caller
    RETURN a / b
END FUNCTION

# the test
PUBLIC FUNCTION test_divide_by_zero_raises()
    CALL Assertions.assertThrows(FUNCTION dbz_call,
        "divide(10, 0) should raise")
END FUNCTION

PRIVATE FUNCTION dbz_call()
    DEFINE x INTEGER
    WHENEVER ANY ERROR RAISE        -- propagate to assertThrows
    LET x = divide(10, 0)
END FUNCTION
```

**`RAISE` only propagates one frame.** Every intermediate function needs
its own `WHENEVER ANY ERROR RAISE`. If you forget it on any frame, the
error stops there and `assertThrows` reports a failure ("no error was
raised").

**Some errors propagate without `RAISE`.** I/O and form-loading errors
(e.g. `OPEN WINDOW WITH FORM "missing"`) reach `TRY/CATCH` directly
without needing `RAISE`. This works because they're not classified as
expression errors. If the function-under-test naturally produces such
an error you can skip the `WHENEVER` boilerplate.

## Skipping tests

Call `skip(msg)` from inside a test:

```4gl
PUBLIC FUNCTION test_requires_database()
    IF NOT db_available() THEN
        CALL Assertions.skip("DB not configured for this environment")
        RETURN
    END IF
    -- regular assertions
END FUNCTION
```

Skipped tests show as `-` and don't count toward fail/error totals.

## Running tests

```
fglrun my_tests.42m [options]
```

| Flag | Effect |
|---|---|
| `--junit <file>` | Write JUnit XML to `<file>` |
| `--filter <pat>` | Run only tests whose name contains `<pat>` (substring) |
| `--list` | Print registered test names and exit 0 |
| `-v`, `--verbose` | Show duration and failure details for every test |
| `--fail-fast` | Stop on first FAIL or ERROR |
| `--color <mode>` | `auto` (default), `always`, `never` |
| `-h`, `--help` | Print usage |

Exit code: `0` when all pass, `1` if any FAIL or ERROR.

Color is auto-detected via `$TERM` — set `TERM=dumb` (or `--color never`)
to disable in CI logs.

## Discovery & running a whole test tree

The hand-written `MAIN` works, but two optional tools remove the
boilerplate: **`fglunit-gen`** writes the runner for you, and
**`fglunit-run`** runs many suites into one report. Both are pure BDL,
ship inside the package, and run via `fglpkg bdl fglunit <tool> …` (or
directly with `fglrun com/fourjs/fglunit/<tool>.42m …` from a build).

> **Paths under `fglpkg bdl`.** `fglpkg bdl` runs the tool with the working
> directory set to the installed-package directory, so pass **absolute**
> file/program paths (or a `--dir <absolute>`). When you invoke the
> compiled tool directly with `fglrun`, ordinary relative paths work since
> the working directory is your own.

### `fglunit-gen` — generate a runner from a test module

Write a test module as a **plain `.4gl`** — no `PACKAGE`, no `MAIN`, no
`register()` calls — containing only `PUBLIC` functions:

```4gl
# test_Calculator.4gl
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL Calculator

PUBLIC FUNCTION setUp()                       -- optional fixture
END FUNCTION

PUBLIC FUNCTION test_add()
    CALL Assertions.assertEqualsInt(5, Calculator.add(2, 3), "2 + 3")
END FUNCTION
```

The generator discovers symbols **by name**:

| Function name (must be `PUBLIC`) | Becomes |
|---|---|
| `test*` (case-insensitive) | a registered test case |
| `setUp` | per-test setup |
| `tearDown` | per-test teardown |
| `setUpSuite` | once-before-all |
| `tearDownSuite` | once-after-all |

```bash
fglpkg bdl fglunit fglunit_gen test_Calculator.4gl
# -> writes test_Calculator.run.4gl (the MAIN + registrations)
fglcomp -M test_Calculator.run.4gl
fglrun test_Calculator.run.42m
```

| Flag | Effect |
|---|---|
| `--dir <d>` | Discover every `test_*.4gl` under `<d>` (non-recursive) |
| `--out <file>` | Output path (single input only; default `<base>.run.4gl`) |
| `--suite <name>` | Override suite name (default derived from the file name) |
| `--stdout` | Write the generated runner to stdout |
| `-h`, `--help` | Usage |

Fixtures and tests **must be `PUBLIC`** so the generated runner can take
function pointers to them. A duplicate test name or duplicate fixture is a
hard error (non-zero exit). A module with no `test*` functions is skipped
with a warning. The generated file carries a `DO NOT EDIT` header; it is
`.gitignore`d by default (`*.run.4gl`).

### `fglunit-run` — aggregate many suites

Run several compiled suites as child processes and merge them into one
report and one exit code:

```bash
fglpkg bdl fglunit fglunit_run --junit out/junit.xml \
    test_Calculator.run.42m test_Strings.run.42m
```

```
  v Calculator: 8 tests, 0 failed, 0 errors, 0 skipped (0.012 s)
  v Strings:    5 tests, 0 failed, 0 errors, 0 skipped (0.004 s)

Suites: 2  Tests: 13  Passed: 13  Failed: 0  Errors: 0  Skipped: 0
```

| Flag | Effect |
|---|---|
| `--dir <d>` | Run every `*.run.42m` under `<d>` (non-recursive) |
| `--junit <file>` | Write the aggregated `<testsuites>` XML |
| `--filter <pat>` | Passed through to each child suite |
| `--fail-fast` | Stop after the first failing suite |
| `-v`, `--verbose` | Echo each child's console output |
| `--color <mode>` | `auto` (default) \| `always` \| `never` |

Each child runs in its own process, so a suite that **crashes** (abnormal
exit, no usable JUnit) is reported as an errored suite — with the captured
output and a retained log path — instead of being silently dropped. Exit
code is `0` only when every suite passes.

The `examples/` directory shows the full chain (generate → compile →
aggregate) driven from a `Makefile`.

## JUnit XML for CI

```bash
fglrun my_tests.42m --junit out/junit.xml
```

Produces a `<testsuite>` document with one `<testcase>` per registered
test. `<failure>`, `<error>`, and `<skipped>` children are added as
appropriate. The format is consumed natively by Jenkins, GitLab CI,
GitHub Actions test reporters, etc.

A typical `Makefile` target:

```make
test:
	fglrun my_tests.42m --junit junit.xml
```

For GitHub Actions, add the `dorny/test-reporter` action and point it
at `junit.xml`.

## Failure vs Error

fglunit reports four outcomes per test:

| Outcome | Symbol | Meaning |
|---|---|---|
| **PASS** | `v` | All assertions succeeded, no error escaped |
| **FAIL** | `x` | An assertion explicitly returned false (`assertEquals`, `assertTrue`, `fail()`, etc.) |
| **ERROR** | `E` | An unexpected runtime error escaped the test (uncaught division by zero, NULL deref, SQL error, etc.) |
| **SKIP** | `-` | The test called `skip()` |

**Why two failure modes?** A FAIL is a problem with the *thing under
test*; the assertion itself worked correctly. An ERROR is a problem
either with the test's setup (e.g. a NULL got past validation) or with
the framework's ability to handle the input. Both fail the build, but
distinguishing them speeds up diagnosis.

**Stack trace reporting.**
- For **FAIL**, fglunit captures the stack inside the assertion (before
  it returns) so the failure message includes the test's file:line
  ("at my_tests.4gl:42"). This works because the stack is still intact
  at that point.
- For **ERROR**, BDL's `TRY/CATCH` unwinds the stack before reaching
  `CATCH`, so a fresh `getStackTrace()` would only show the runner.
  fglunit relies on `err_get(status)` instead — that message string
  carries the offending line for most error types.

## When to use fglunit vs GGC

Use **fglunit** for:
- Pure functions and library modules (math, parsing, formatting)
- Data type behavior (records, dynamic arrays, dictionaries)
- Database/repository layer functions (with a test schema)
- Anything you'd call directly from another `.4gl` module

Use **GGC (Genero Ghost Client)** for:
- End-to-end UI flows (open form, fill fields, fire actions, verify
  state)
- Master/detail dialog interactions
- Anything that requires driving the AUI protocol from the outside

The two coexist happily: a project's `tests/` directory can hold
fglunit unit suites and GGC scenarios side by side.

## Limitations

- **No function reflection.** BDL can't enumerate `test*` symbols at
  runtime, so registration is explicit — either hand-written, or generated
  at build time by [`fglunit-gen`](#discovery--running-a-whole-test-tree).
- **Discovery is a line scanner, not a full parser.** `fglunit-gen` reads
  source text (skipping `{ }` and `--` / `#` comments); exotic formatting
  may need the hand-written style. It is non-recursive (`--dir` scans one
  level).
- **No mocking framework in v1.** Use real (test) databases, real
  fixtures, or hand-rolled test doubles. A stub/spy module may follow
  in v2.
- **No parallel test execution.** Tests run sequentially in
  registration order.
- **No parametrized tests in v1.** Use one function per parameter set,
  or call a private helper from each test.
- **`assertThrows` requires `WHENEVER ANY ERROR RAISE`** on every frame
  in the call path for expression errors. See
  [Testing error paths](#testing-error-paths).

---

Issues / improvements: file at the package's repo. Contributions welcome.
