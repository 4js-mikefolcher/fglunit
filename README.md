# fglunit

An xUnit-style unit testing framework for Genero BDL — assertions, fixtures,
JUnit XML output, CI-friendly exit codes.

The library is pure BDL with no dependencies outside the runtime: write a
suite, compile it, run the `.42m`. Two **optional** tools go further —
`fglunit-gen` generates runner modules from your test source, and
`fglunit-run` executes several compiled suites as child processes and
merges their reports. Neither is needed to write or run tests.

## Why

Genero ships with **GGC (Genero Ghost Client)** for functional/end-to-end UI
testing, but there is no idiomatic library for **unit testing** pure
functions, data types, and library modules. Using GGC for that forces every
test suite through `ggcadmin`, a TCP handshake, and a no-op target program.

`fglunit` fills the unit-test gap. GGC stays the right tool for form- and
dialog-level integration testing.

## Requirements

Genero BDL **4.00 or newer** — `fglunit` uses `util.Regexp` (`assertMatches`)
and `STRING.replaceAll` (JUnit XML escaping), both introduced in 4.00.

## Install

```bash
fglpkg install fglunit
eval "$(fglpkg env --local)"
```

## 30-second example

```4gl
IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs

MAIN                                   -- MAIN comes before any FUNCTION
    CALL CliArgs.parse()               -- enables the flags listed below
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

Run it:

```bash
fglcomp -M my_tests.4gl
fglrun my_tests.42m
```

Output:

```
basic math
  v test_addition
  v test_string_contains

Tests: 2  Passed: 2  Failed: 0  Errors: 0  Skipped: 0  Time: 1 ms
```

## CLI flags

| Flag | Purpose |
|---|---|
| `--junit <file>` | Write JUnit XML for CI consumption |
| `--filter <pattern>` | Run only tests whose name contains `<pattern>` |
| `--list` | Print registered test names and exit 0 |
| `-v` / `--verbose` | Per-test output |
| `--fail-fast` | Stop on first failure |
| `--allow-empty` | Exit `0` even when no test ran |
| `--color never\|always\|auto` | Force / disable ANSI color |

Exit code is `0` when every test passed, `1` on a failure **or when no
test ran at all** (a mistyped `--filter` should not produce a green
build), `2` on a usage error.

## Discovery & running a whole test tree

Writing the `MAIN` and a `register()` line per test gets old. Two optional
tools remove that:

- **`fglunit-gen`** scans a plain test module (no `MAIN`) for
  `PUBLIC FUNCTION test*` cases plus `setUp` / `tearDown` /
  `setUpSuite` / `tearDownSuite` fixtures, and generates the runner for you.
- **`fglunit-run`** runs many compiled suites as child processes and merges
  them into one `<testsuites>` report with a combined exit code — a crashing
  suite is reported as an error, never silently dropped.

```bash
# write test_Calculator.4gl as plain PUBLIC FUNCTION test*() — no MAIN
fglpkg bdl fglunit fglunit_gen test_Calculator.4gl   # -> test_Calculator.run.4gl
fglcomp -M test_Calculator.run.4gl
fglpkg bdl fglunit fglunit_run --junit out.xml test_Calculator.run.42m other.run.42m
```

Both tools ship with the package and run via `fglpkg bdl fglunit <tool>`
(or directly: `fglrun com/fourjs/fglunit/fglunit_gen.42m …`). The
hand-written `MAIN` style above still works unchanged — discovery is
opt-in. See the [User Guide](USERGUIDE.md#discovery--running-a-whole-test-tree)
for the conventions and full flag list.

## Documentation

See [USERGUIDE.md](USERGUIDE.md) for the full API, fixtures (setup / teardown),
discovery & aggregation, CI recipes, and failure-vs-error semantics.

## License

MIT — see [LICENSE](LICENSE).
