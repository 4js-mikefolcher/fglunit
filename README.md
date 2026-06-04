# fglunit

An xUnit-style unit testing framework for Genero BDL — assertions, fixtures,
JUnit XML output, CI-friendly exit codes. Pure BDL, no GGC or shell tooling
required.

## Why

Genero ships with **GGC (Genero Ghost Client)** for functional/end-to-end UI
testing, but there is no idiomatic library for **unit testing** pure
functions, data types, and library modules. Using GGC for that forces every
test suite through `ggcadmin`, a TCP handshake, and a no-op target program.

`fglunit` fills the unit-test gap. GGC stays the right tool for form- and
dialog-level integration testing.

## Install

```bash
fglpkg install fglunit
eval "$(fglpkg env --local)"
```

## 30-second example

```4gl
IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions

PUBLIC FUNCTION test_addition()
    CALL Assertions.assertEqualsInt(4, 2 + 2, "2 + 2 should equal 4")
END FUNCTION

PUBLIC FUNCTION test_string_contains()
    CALL Assertions.assertContains("hello world", "world", "substring match")
END FUNCTION

MAIN
    CALL FglUnit.suite("basic math")
    CALL FglUnit.register("test_addition",       FUNCTION test_addition)
    CALL FglUnit.register("test_string_contains", FUNCTION test_string_contains)
    EXIT PROGRAM FglUnit.run()
END MAIN
```

Run it:

```bash
fglcomp -M my_tests.4gl
fglrun my_tests.42m
```

Output:

```
basic math
  ✓ test_addition (0 ms)
  ✓ test_string_contains (0 ms)

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
| `--color never\|always\|auto` | Force / disable ANSI color |

Exit code is `0` when all pass, `1` otherwise.

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
fglrun bin/fglunit_gen.42m test_Calculator.4gl     # -> test_Calculator.run.4gl
fglcomp -M test_Calculator.run.4gl
fglrun bin/fglunit_run.42m --junit out.xml test_Calculator.run.42m other.run.42m
```

The hand-written `MAIN` style above still works unchanged — discovery is
opt-in. See the [User Guide](USERGUIDE.md#discovery--running-a-whole-test-tree)
for the conventions and full flag list.

## Documentation

See [USERGUIDE.md](USERGUIDE.md) for the full API, fixtures (setup / teardown),
discovery & aggregation, CI recipes, and failure-vs-error semantics.

## License

MIT — see [LICENSE](LICENSE).
