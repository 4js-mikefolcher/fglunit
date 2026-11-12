# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

`fglpkg publish` reads the section matching the version in `fglpkg.json`,
so every release needs an entry here before it is published.

## [Unreleased]

### Fixed

- **Non-ASCII text was corrupted in the JUnit report.** With
  `FGL_LENGTH_SEMANTICS` at its default (`BYTE`), "café" was written as
  "caf" and two blanks, in test names, failure messages and the suite
  name. The XML escaping now removes the forbidden control characters
  without copying the text one character at a time, so multibyte text comes
  out as it went in under either setting. `test_Reporter` and
  `test_Internal` now run under both `BYTE` and `CHAR`.

## [1.1.0]

### Added

- **Parametrized tests:** `FglUnit.registerCases(name, fn, cases)` runs `fn`
  once per row, each row its own test (`name[1]`, `name[2]`, ...). A
  failing row prints the row; an empty table, or a row that is not a
  record, fails rather than vanishing or crashing.
- **Fuzz targets:** `FglUnit.registerFuzz(name, fn, runs)` and the new
  `Fuzz` module: seeded, deterministic generators for `INTEGER`, strings,
  `DATE`, `DECIMAL`, `BOOLEAN` and array counts, with boundary values and
  NULL. A failing run is shrunk by input size and reported with its seed,
  size, inputs and replay options. `skip()` inside a run discards that
  input and the target carries on; it is reported as skipped only when
  every run was, and a pass that discarded some runs says how many were
  tested (`1 of 100 runs tested, 99 skipped`); the JUnit report carries
  that text in a `<system-out>` element on the passing testcase. The replay
  line is quoted for the shell and names any other test that `--filter`
  would also select. On Windows, a name that cmd.exe cannot quote safely
  gets the placeholder `NAME` and a note instead of a line that would
  misparse.
  Seeds are scrambled, so consecutive runs draw unrelated values. A
  multibyte character is generated only with `FGL_LENGTH_SEMANTICS=CHAR`
  in a UTF-8 locale, and as `?` otherwise, so a length limit is exact in
  every environment.
- `--seed`, `--fuzz-runs` and `--fuzz-size` on the suite runner, and
  forwarded by `fglunit-run`. A value that is not a whole number in range
  exits 2.
- Self-tests, integration checks and `examples/CalculatorFuzz.4gl`. The
  `Fuzz` self-tests run under both `BYTE` and `CHAR` length semantics.
  `make -C tests` runs every suite and fails at the end, so one failing
  suite no longer hides the ones after it.

## [1.0.1]

No changes to the package. Only the version number in `fglpkg.json` differs
from 1.0.0; the source, tools and documentation are identical.

## [1.0.0]

The first public release. It contains exactly the changes listed under
0.2.2 below: that was the version number the manifest carried while the
work was in progress, and it was released as 1.0.0 instead. There was never
a 0.2.2 release. Read **Changed** under 0.2.2 before upgrading a CI
pipeline.

## [0.2.2]

First release intended for public consumption. Several of these are
behaviour changes: read **Changed** before upgrading a CI pipeline.

### Fixed

- **Assertions passed when handed a NULL.** `assertTrue`, `assertFalse`,
  `assertEqualsInt` and `assertEqualsDec` all reported success for a NULL
  argument, because BDL evaluates both `NULL = x` and `NULL != x` as
  false. They now test NULL explicitly and report it as `<NULL>`.
- **`fglunit-gen` silently dropped tests.** A single `{` inside a string
  literal opened a block comment that swallowed the rest of the file;
  every test function after it vanished from the generated runner with a
  zero exit code. The scanner now tracks string literals.
- **Invalid JUnit XML.** Raw control characters (an ANSI escape in a
  failure message, say) reached the report and made the whole document
  unparseable, which also caused `fglunit-run` to report the suite as
  crashed. They are now stripped before escaping.
- **Shell injection in `fglunit-run`.** The program path and `--filter`
  value were interpolated into a command handed to a shell. They are now
  quoted per platform, and values that quoting cannot neutralize are
  refused.
- **`tearDown` was skipped when a test raised** — exactly when cleanup
  matters most. It now runs unconditionally, as JUnit's `@After` does.
- **A suite fixture that raised killed the program** with no report; it
  is now recorded as an error.
- **`skip()` could bury a real failure.** A failing assertion after a
  `skip()` was reported as SKIP. A failure now outranks a skip.
- `--list` ignored `--filter`.
- Discovery scanning was quadratic: a 116 KB module took 27 s, now 0.14 s.
- `--dir` returned files in filesystem order, so suite order varied by
  machine. Both tools now sort.
- Temp files in `fglunit-run` had guessable names in a world-writable
  directory.
- A non-numeric attribute in a child report turned every aggregated total
  into NULL rather than affecting only that suite.
- The headline example in README and USERGUIDE did not compile: BDL
  requires `MAIN` to precede every `FUNCTION`.

### Changed

- **A run that executes no test now exits 1**, rather than reporting
  success. A mistyped `--filter` or an unwired suite previously produced
  a green build over an empty run. Pass `--allow-empty` where that is
  intended. Applies to both the suite runner and `fglunit-run`.
- A `test*` function that takes parameters or returns a value is skipped
  with a warning instead of being registered into a runner that then
  fails to compile.
- `auto` colour now also honours `NO_COLOR`.

### Added

- `--allow-empty` on both the suite runner and `fglunit-run`.
- `Internal` module holding the helpers previously duplicated across
  Reporter, Aggregator and the two tools. Not public API.
- Self-tests for Reporter and Internal, `tests/integration.sh` for
  process-level behaviour, and `ci/checks.py` for repository checks that
  need no Genero toolchain. Self-tests 45 -> 80.
- `LICENSE` and `README.md` now ship inside the package.
- Documented minimum: Genero BDL 4.00.

## [0.2.1]

- Ship the tools as package programs; make the driver OS-agnostic.
- Test discovery and multi-suite aggregation.
