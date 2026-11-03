# fglunit — User Guide

xUnit-style unit testing for Genero BDL.

Writing and running a suite needs nothing beyond the BDL runtime: no GGC
server, no code generation, no shell. The two optional tools in
[Discovery & running a whole test tree](#discovery--running-a-whole-test-tree)
do generate code (`fglunit-gen`) and do spawn child processes through a
shell (`fglunit-run`) — that is the trade they make, and you can ignore
both.

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
11. [Parametrized tests and fuzzing](#parametrized-tests-and-fuzzing)
12. [JUnit XML for CI](#junit-xml-for-ci)
13. [Failure vs Error](#failure-vs-error)
14. [When to use fglunit vs GGC](#when-to-use-fglunit-vs-ggc)
15. [Testing fglunit itself](#testing-fglunit-itself)
16. [Limitations](#limitations)

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

> **NULL is never quietly equal.** BDL evaluates both `NULL = x` and
> `NULL != x` as false, so an assertion written the obvious way *passes*
> when handed a NULL. Every fglunit assertion tests NULL explicitly:
> NULL equals NULL, NULL differs from every other value, and a NULL
> shows as `<NULL>` in the failure message. `assertTrue(NULL)` and
> `assertFalse(NULL)` both fail — NULL is neither. A NULL `tolerance`
> in `assertEqualsDec` means exact match, not match-anything.

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
does not run. `tearDown` runs regardless — after a pass, a failure, a
skip, an error, and after a `setUp` that raised. That matches JUnit's
`@After`, and it is when the body blew up that the cleanup matters most:
a connection left open or a temp table left behind leaks into every
later test.

If `tearDown` itself raises, the test is marked **ERROR**, but a failure
or error already recorded for the body is never overwritten by it.

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

> **`skip()` does not abort the test.** BDL gives the framework no way to
> unwind the call stack, so execution continues on the next line — always
> follow `skip()` with `RETURN`, as above. If an assertion *does* run
> afterwards and fails, the test reports **FAIL**, not SKIP: a real
> failure is never hidden behind a skip.

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
| `--allow-empty` | Exit `0` even when no test ran |
| `--seed <n>` | Base seed for fuzz targets (see [fuzzing](#parametrized-tests-and-fuzzing)) |
| `--fuzz-runs <n>` | Runs per fuzz target; `0` skips them |
| `--fuzz-size <n>` | Input size 0-100; replays a failure without shrinking it |
| `--color <mode>` | `auto` (default), `always`, `never` |
| `-h`, `--help` | Print usage |

Exit codes: `0` when every test passed, `1` on a FAIL or ERROR **or when
no test ran at all**, `2` on a usage error.

> **A run that executed nothing fails.** A mistyped `--filter`, or a
> suite whose `register()` calls were never wired up, would otherwise
> hand CI a green build over an empty run. fglunit prints what happened
> and exits `1`. Pass `--allow-empty` where an empty run is legitimate —
> a suite whose tests are all filtered out by design, say.

**Color.** `--color always` and `--color never` are absolute. Under
`auto` (the default), fglunit disables color when `NO_COLOR` is set to
anything at all ([no-color.org](https://no-color.org)), and when `TERM`
is unset or `dumb`.

> `auto` cannot tell a terminal from a redirect. BDL exposes no `isatty`,
> so `fglrun my_tests.42m > log.txt` still writes escape sequences into
> the file. Use `--color never` or `NO_COLOR=1` when capturing output.
> (`fglunit-run` already forces `--color never` on the children it
> spawns, so aggregated runs are unaffected.)

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
function pointers to them, and each must be a `TestHandler` — no
parameters, no return value. A `test*` function that takes parameters (a
helper, usually) or returns a value is **skipped with a warning** naming
it, rather than registered into a runner that then fails to compile.

A duplicate test name or duplicate fixture is a hard error (non-zero
exit). A module with no `test*` functions is skipped with a warning. The
generated file carries a `DO NOT EDIT` header; it is `.gitignore`d by
default (`*.run.4gl`).

`--dir` sorts the files it finds, so a directory sweep produces the same
suite order — and the same aggregated report — on every machine.

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
| `--allow-empty` | Exit `0` even when no suite ran a single test |
| `-v`, `--verbose` | Echo each child's console output |
| `--color <mode>` | `auto` (default) \| `always` \| `never` |

Each child runs in its own process, so a suite that **crashes** (abnormal
exit, no usable JUnit) is reported as an errored suite — with the captured
output — instead of being silently dropped. Exit code is `0` only when
every suite passes and at least one test actually ran.

The `examples/` directory shows the full chain (generate → compile →
aggregate) driven from a `Makefile`.

## Parametrized tests and fuzzing

Two registration calls go beyond `register`: **`registerCases`** runs one
test function once per row of a table, and **`registerFuzz`** runs a test
function many times with generated inputs. Both are called from a
hand-written `MAIN`; `fglunit-gen` does not generate them. A fuzz test is
an ordinary test whose inputs are generated, so it uses the same
assertions, fixtures, filters, JUnit output and exit codes.

### Parametrized tests

Describe the rows as a record type, fill an array, and hand it over as
JSON. The test function receives one row as a `util.JSONObject` and turns
it back into the record with `toFGL`:

```4gl
IMPORT util

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL Calculator

PRIVATE TYPE tDivision RECORD
   dividend INTEGER,
   divisor  INTEGER,
   expected INTEGER
END RECORD

MAIN
   VAR rows DYNAMIC ARRAY OF tDivision
   CALL CliArgs.parse()
   LET rows[1].dividend = 10
   LET rows[1].divisor = 2
   LET rows[1].expected = 5
   LET rows[2].dividend = -9
   LET rows[2].divisor = 3
   LET rows[2].expected = -3
   CALL FglUnit.registerCases("divide", FUNCTION checkDivide,
      util.JSONArray.fromFGL(rows))
   EXIT PROGRAM FglUnit.run()
END MAIN

PRIVATE FUNCTION checkDivide(args util.JSONObject) RETURNS ()
   VAR row tDivision
   CALL args.toFGL(row)
   CALL Assertions.assertEqualsInt(row.expected, Calculator.divide(row.dividend, row.divisor),
      SFMT("%1 / %2", row.dividend, row.divisor))
END FUNCTION
```

Each row is its own test, named `divide[1]`, `divide[2]`, ..., so
`--filter`, `--list`, the console and the JUnit report all see them
individually. A failing row prints the row itself:

```
  x divide[2]
      case {"dividend":-9,"divisor":3,"expected":-4}
      assertEqualsInt failed: -9 / 3
```

- An **empty table fails** (`registerCases: the table has no rows`) rather
  than silently registering nothing.
- `toFGL` matches members by name, case-insensitively, and turns a member
  whose type does not match into NULL without an error. Declare the row
  members with the same types the test uses, and `assertNotNull` a member
  you depend on.

### Fuzz targets

`registerFuzz(name, fn, runs)` calls `fn` `runs` times (`NULL` means 100).
`fn` is a plain test function that draws its inputs from the `Fuzz` module
and checks a property that must hold for every input:

```4gl
IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL com.fourjs.fglunit.Fuzz
IMPORT FGL Calculator

MAIN
   CALL CliArgs.parse()
   CALL FglUnit.registerFuzz("maxIsNotBelowEitherArgument", FUNCTION propMaxBounds, 200)
   EXIT PROGRAM FglUnit.run()
END MAIN

PRIVATE FUNCTION propMaxBounds() RETURNS ()
   VAR a INTEGER
   VAR b INTEGER
   VAR m INTEGER
   CALL Fuzz.setNullRate(0)
   LET a = Fuzz.nextInt(NULL, NULL)
   LET b = Fuzz.nextInt(NULL, NULL)
   LET m = Calculator.max(a, b)
   CALL Assertions.assertTrue(m >= a AND m >= b, SFMT("max(%1, %2) = %3", a, b, m))
END FUNCTION
```

The generators (`Fuzz` module). All of them are deterministic from the
seed, so a run is repeatable on every platform:

| Function | Besides random values, it produces |
|---|---|
| `nextInt(lowest, highest)` | the bounds, the bounds +/- 1, 0, 1, -1; the whole `INTEGER` range when the bounds are `NULL` |
| `nextString(maxLength)` | blanks, quotes, `%` and `*`, a backslash, SQL / JSON / markup fragments, tabs, newlines, ESC, multibyte UTF-8, a combining accent, a string of exactly `maxLength` |
| `nextDate()` | 31/12/1899, 1/1/1, 29 February, 31/12/9999 |
| `nextDecimal(lowest, highest)` | the bounds, 0, plus or minus 0.0000000001 |
| `nextBoolean()` | `TRUE`, `FALSE` |
| `nextCount(highest)` | 0, 1, `highest` (the length of an array to build; never `NULL`) |

- **NULL is generated by default** (5 percent of values), because it is the
  commonest BDL edge case. `Fuzz.setNullRate(0)` turns it off for the rest
  of the run; `setNullRate(100)` makes everything NULL. An empty string is
  NULL in BDL, so it is covered by the NULL rate.
- The generators can be used in an ordinary test too: call
  `Fuzz.seed(n)` first for a repeatable stream.
- A target fails when an assertion fails or when it raises a runtime error.
  Expression errors such as division by zero propagate only through
  functions that declare `WHENEVER ANY ERROR RAISE`, exactly as for
  [`assertThrows`](#testing-error-paths).

**Seeds and replay.** `run` *k* of a target uses seed *base + k - 1*. The
base seed comes from the clock and is printed at the start (`fuzz seed
142241984`); `--seed` fixes it. The first failing run stops the target.

**Shrinking.** After a failure, the runner re-runs the same seed at smaller
*sizes*: at a small size numbers stay near 0, dates near 1 January 2000, and
strings and counts are short. It keeps the smallest size that still fails
and reports it with the inputs that were drawn:

```
  x badFuzz
      fuzz: failed on run 1 of 200
        seed:   142241984
        size:   26 (shrunk from 100)
        inputs: str="p^iT^?\t!"Szhg5sGxq" (18 chars)
        replay: --filter badFuzz --seed 142241984 --fuzz-size 26 --fuzz-runs 1
      assertTrue failed: length 18 exceeds 10
```

Run the `replay:` options to reproduce that exact failure. An explicit
`--fuzz-size` runs at that size and does not shrink again, so the replay
shows the same inputs. A runtime error shrinks the same way (a division by
zero typically shrinks to `int=0` at size 0).

| Option | Effect |
|---|---|
| `--seed <n>` | Base seed (any whole number; it is folded into 1 .. 2147483646) |
| `--fuzz-runs <n>` | Override the runs of every fuzz target; `0` skips them (reported as SKIP) |
| `--fuzz-size <n>` | Fix the input size (0-100); disables shrinking |

`fglunit-run` forwards all three to each suite.

**What fuzzing here is not.** The shrinker is a heuristic: it searches
sizes for one seed, so the reported size is a local minimum and a failure
need not be monotonic in size. There are no saved corpus files, no
coverage guidance, and no generators for `BIGINT`, `FLOAT`, `INTERVAL` or
records; build those from the primitives above. Inputs are drawn by the
test, not derived from a function's signature.

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

## Testing fglunit itself

`FglUnit.takeFailure()` reads **and clears** the current test's failure
flag, returning whether one was set. It exists for meta-tests — a suite
that checks an assertion correctly *detects* a failure has to consume
the flag it just tripped, or the meta-test itself would fail:

```4gl
PUBLIC FUNCTION test_assertEquals_detects_a_mismatch()
    CALL Assertions.assertEquals("a", "b", "should trip")
    CALL Assertions.assertTrue(FglUnit.takeFailure(),
        "assertEquals('a','b') should have tripped the failure flag")
END FUNCTION
```

> It is `PUBLIC` because fglunit's own suites live outside the package,
> not because ordinary tests should call it. Calling it in a normal test
> **swallows a real failure** and turns a red test green. If you are not
> testing an assertion, you do not want this function.

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
- **Parametrized tests and fuzz targets are registered by hand.**
  `fglunit-gen` does not discover them; see
  [Parametrized tests and fuzzing](#parametrized-tests-and-fuzzing).
- **`assertThrows` requires `WHENEVER ANY ERROR RAISE`** on every frame
  in the call path for expression errors. See
  [Testing error paths](#testing-error-paths).

---

Issues / improvements: file at the package's repo. Contributions welcome.
