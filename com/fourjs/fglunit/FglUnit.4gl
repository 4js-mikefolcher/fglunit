PACKAGE com.fourjs.fglunit

IMPORT os
IMPORT util

IMPORT FGL com.fourjs.fglunit.Reporter
IMPORT FGL com.fourjs.fglunit.Fuzz
IMPORT FGL com.fourjs.fglunit.Internal

# Public types -------------------------------------------------------

PUBLIC TYPE TestHandler FUNCTION() RETURNS ()

# A parametrized test: called once per case, with the case as a JSON
# object. Convert it to a record with args.toFGL(rec).
PUBLIC TYPE CaseHandler FUNCTION(args util.JSONObject) RETURNS ()

PUBLIC CONSTANT STATUS_PASS  = "PASS"
PUBLIC CONSTANT STATUS_FAIL  = "FAIL"
PUBLIC CONSTANT STATUS_ERROR = "ERROR"
PUBLIC CONSTANT STATUS_SKIP  = "SKIP"

PUBLIC TYPE TestResult RECORD
    name STRING,
    status STRING,
    message STRING,
    location STRING,
    durationMs INTEGER
END RECORD

# Module-private state ----------------------------------------------

PRIVATE CONSTANT cKindCase = "case"
PRIVATE CONSTANT cKindBadRow = "badrow"
PRIVATE CONSTANT cKindFuzz = "fuzz"
PRIVATE CONSTANT cDefaultFuzzRuns = 100

# kind is NULL for a plain test. A case carries its row as JSON text and
# runs through the runCase trampoline; a row that is not a record carries
# its failure message in args instead; a fuzz target carries its run count.
PRIVATE TYPE Registration RECORD
    name STRING,
    fn TestHandler,
    kind STRING,
    argFn CaseHandler,
    args STRING,
    runs INTEGER
END RECORD

PRIVATE DEFINE suiteName STRING
PRIVATE DEFINE setUpFn TestHandler
PRIVATE DEFINE tearDownFn TestHandler
PRIVATE DEFINE setUpSuiteFn TestHandler
PRIVATE DEFINE tearDownSuiteFn TestHandler
PRIVATE DEFINE registry DYNAMIC ARRAY OF Registration
PRIVATE DEFINE results DYNAMIC ARRAY OF TestResult

# Flag set by Assertions.* when a test records a failure or skip.
# Reset between tests by runOne().
PRIVATE DEFINE failureSeen BOOLEAN
PRIVATE DEFINE skipSeen BOOLEAN
PRIVATE DEFINE failureMsg STRING
PRIVATE DEFINE failureLoc STRING
# Kept apart from failureMsg: a test that skips AND fails must not lose
# the failure text behind the skip reason.
PRIVATE DEFINE skipMsg STRING

# Runtime options (set via CliArgs.parse + setters)
PRIVATE DEFINE optVerbose BOOLEAN
PRIVATE DEFINE optFilter STRING
PRIVATE DEFINE optListOnly BOOLEAN
PRIVATE DEFINE optFailFast BOOLEAN
PRIVATE DEFINE optJunit STRING
PRIVATE DEFINE optColor STRING     # "auto" | "always" | "never"
PRIVATE DEFINE optAllowEmpty BOOLEAN
# An unset number is 0 in BDL, not NULL, and 0 is a meaningful value for
# all three (--fuzz-runs 0 skips fuzz targets), so each carries a flag.
PRIVATE DEFINE optFuzzSeed BIGINT
PRIVATE DEFINE optFuzzSeedSet BOOLEAN
PRIVATE DEFINE optFuzzRuns INTEGER
PRIVATE DEFINE optFuzzRunsSet BOOLEAN
PRIVATE DEFINE optFuzzSize INTEGER
PRIVATE DEFINE optFuzzSizeSet BOOLEAN

# Fuzz and case state: the base seed of this run, and the case being run
# (read by the runCase trampoline, because a TestHandler takes no argument).
PRIVATE DEFINE fuzzBase BIGINT
PRIVATE DEFINE activeArgFn CaseHandler
PRIVATE DEFINE activeArgs STRING

# Public API: suite config + registration ---------------------------

PUBLIC FUNCTION suite(name STRING)
    LET suiteName = name
END FUNCTION

PUBLIC FUNCTION setSetup(fn TestHandler)
    LET setUpFn = fn
END FUNCTION

PUBLIC FUNCTION setTeardown(fn TestHandler)
    LET tearDownFn = fn
END FUNCTION

PUBLIC FUNCTION setSetupSuite(fn TestHandler)
    LET setUpSuiteFn = fn
END FUNCTION

PUBLIC FUNCTION setTeardownSuite(fn TestHandler)
    LET tearDownSuiteFn = fn
END FUNCTION

PUBLIC FUNCTION register(name STRING, fn TestHandler)
    DEFINE r Registration
    LET r.name = name
    LET r.fn = fn
    LET registry[registry.getLength() + 1].* = r.*
END FUNCTION

#+ Register one test per row of cases. Each run is named name[1], name[2],
#+ ... and calls fn with the row as a JSON object, so a failure names the
#+ row. Build cases with util.JSONArray.fromFGL(rows), where rows is a
#+ DYNAMIC ARRAY OF a named record type. An empty table, and a row that is
#+ not a record (a table of plain integers, say), are reported as failing
#+ tests, never silently dropped and never a crash.
PUBLIC FUNCTION registerCases(name STRING, fn CaseHandler,
      cases util.JSONArray) RETURNS ()
   VAR r Registration
   VAR row util.JSONObject
   VAR i INTEGER
   IF cases IS NULL OR cases.getLength() == 0 THEN
      LET r.name = name
      LET r.fn = FUNCTION emptyCases
      LET registry[registry.getLength() + 1].* = r.*
      RETURN
   END IF
   FOR i = 1 TO cases.getLength()
      INITIALIZE r.* TO NULL
      LET r.name = SFMT("%1[%2]", name, i)
      IF cases.getType(i) == "OBJECT" THEN
         LET row = cases.get(i)
         LET r.fn = FUNCTION runCase
         LET r.kind = cKindCase
         LET r.argFn = fn
         LET r.args = row.toString()
      ELSE
         # Reading a plain value as a record would stop the program with a
         # conversion error. Fail this row by name instead.
         LET r.fn = FUNCTION notARecord
         LET r.kind = cKindBadRow
         LET r.args = SFMT("registerCases: row %1 of '%2' is a %3, not a record "
            || "(build the table from a DYNAMIC ARRAY OF a record type)",
            i, name, downshift(cases.getType(i)))
      END IF
      LET registry[registry.getLength() + 1].* = r.*
   END FOR
END FUNCTION

#+ Register a fuzz target: fn runs runs times (default 100), each run with
#+ a different seed, and fn draws its inputs from the Fuzz module. The
#+ first run that fails is shrunk and reported with its seed, its size and
#+ the inputs, plus the options that replay it. The target fails through
#+ the ordinary assertions or by raising an error.
PUBLIC FUNCTION registerFuzz(name STRING, fn TestHandler, runs INTEGER) RETURNS ()
   VAR r Registration
   LET r.name = name
   LET r.fn = fn
   LET r.kind = cKindFuzz
   LET r.runs = runs
   LET registry[registry.getLength() + 1].* = r.*
END FUNCTION

# Public API: options (usually set by CliArgs) ----------------------

#+ Base seed for fuzz targets (run n uses seed + n - 1). Default: from the clock.
PUBLIC FUNCTION setFuzzSeed(v BIGINT) RETURNS ()
   LET optFuzzSeed = v
   LET optFuzzSeedSet = (v IS NOT NULL)
END FUNCTION

#+ Override the number of runs of every fuzz target. 0 skips them.
PUBLIC FUNCTION setFuzzRuns(v INTEGER) RETURNS ()
   LET optFuzzRuns = v
   LET optFuzzRunsSet = (v IS NOT NULL)
END FUNCTION

#+ Input size for fuzz runs (Fuzz.cFullSize by default). Used to replay a
#+ shrunk failure.
PUBLIC FUNCTION setFuzzSize(v INTEGER) RETURNS ()
   LET optFuzzSize = v
   LET optFuzzSizeSet = (v IS NOT NULL)
END FUNCTION

PUBLIC FUNCTION setVerbose(v BOOLEAN)
    LET optVerbose = v
END FUNCTION

PUBLIC FUNCTION setFilter(pattern STRING)
    LET optFilter = pattern
END FUNCTION

PUBLIC FUNCTION setListOnly(v BOOLEAN)
    LET optListOnly = v
END FUNCTION

PUBLIC FUNCTION setFailFast(v BOOLEAN)
    LET optFailFast = v
END FUNCTION

PUBLIC FUNCTION setJunitOutput(path STRING)
    LET optJunit = path
END FUNCTION

PUBLIC FUNCTION setColorMode(mode STRING)
    LET optColor = mode
END FUNCTION

# Permit a run in which no test executed to still exit 0. Off by default:
# a filter typo, an empty registry or a bad --dir otherwise produces a
# green build that ran nothing at all.
PUBLIC FUNCTION setAllowEmpty(v BOOLEAN)
    LET optAllowEmpty = v
END FUNCTION

PUBLIC FUNCTION getColorMode() RETURNS STRING
    IF optColor IS NULL OR optColor.getLength() == 0 THEN RETURN "auto" END IF
    RETURN optColor
END FUNCTION

PUBLIC FUNCTION getVerbose() RETURNS BOOLEAN
    RETURN optVerbose
END FUNCTION

# Internal hooks — called by Assertions module ----------------------
# Not intended for user code. Kept PUBLIC because cross-module calls
# between fglunit's own modules need visibility.

PUBLIC FUNCTION notifyFailure(message STRING, location STRING)
    # First failure wins (JUnit convention). Later assertions in the
    # same test still run, but the first message is reported.
    IF NOT failureSeen THEN
        LET failureSeen = TRUE
        LET failureMsg = message
        LET failureLoc = location
    END IF
END FUNCTION

PUBLIC FUNCTION notifySkip(message STRING)
    LET skipSeen = TRUE
    LET skipMsg = message
END FUNCTION

# Testing helper: reads and clears the per-test failure flag in one
# atomic step. Returns TRUE if a failure was recorded since the last
# clear (or since the test started). Intended for meta-tests that
# verify assertions correctly detect failures — the assertions under
# test trip the flag, then the meta-test calls takeFailure() to
# consume it (so the meta-test itself still passes).
PUBLIC FUNCTION takeFailure() RETURNS BOOLEAN
    DEFINE was BOOLEAN
    LET was = failureSeen
    LET failureSeen = FALSE
    LET failureMsg = NULL
    LET failureLoc = NULL
    RETURN was
END FUNCTION

# Runner ------------------------------------------------------------

PUBLIC FUNCTION run() RETURNS INTEGER
    DEFINE i INTEGER
    DEFINE r TestResult
    DEFINE passed, failed, errored, skipped INTEGER
    DEFINE startDt DATETIME YEAR TO FRACTION(3)
    DEFINE totalMs INTEGER
    DEFINE selected INTEGER
    DEFINE fixtureErr STRING

    # --list mode: print names and exit 0. The filter applies here too,
    # so `--list --filter x` previews exactly what `--filter x` runs.
    IF optListOnly THEN
        FOR i = 1 TO registry.getLength()
            IF matchesFilter(registry[i].name) THEN
                DISPLAY registry[i].name
            END IF
        END FOR
        RETURN 0
    END IF

    CALL Reporter.onHeader(getSuiteName())

    # Fuzz targets: pick the base seed once and print it, so a failure in
    # CI can be replayed even if the failure text is lost.
    LET fuzzBase = chooseFuzzBase()
    IF countFuzz() > 0 THEN
        DISPLAY SFMT("  fuzz seed %1", fuzzBase)
    END IF

    LET startDt = CURRENT YEAR TO FRACTION(3)

    # A suite fixture that raises used to kill the program outright, with
    # no report and no exit code of our own. Record it as an error so the
    # failure is visible in the console and in the JUnit document.
    IF setUpSuiteFn IS NOT NULL THEN
        LET fixtureErr = callFixture(setUpSuiteFn)
        IF fixtureErr IS NOT NULL THEN
            CALL recordFixtureError("(setUpSuite)", fixtureErr, startDt)
            LET errored = errored + 1
        END IF
    END IF

    IF errored == 0 THEN
        FOR i = 1 TO registry.getLength()
            IF NOT matchesFilter(registry[i].name) THEN
                CONTINUE FOR
            END IF
            LET selected = selected + 1

            CALL runEntry(registry[i].*) RETURNING r.*
            LET results[results.getLength() + 1].* = r.*

            CALL Reporter.onProgress(r.*)

            CASE r.status
                WHEN STATUS_PASS  LET passed  = passed  + 1
                WHEN STATUS_FAIL  LET failed  = failed  + 1
                WHEN STATUS_ERROR LET errored = errored + 1
                WHEN STATUS_SKIP  LET skipped = skipped + 1
            END CASE

            IF optFailFast AND (r.status == STATUS_FAIL OR r.status == STATUS_ERROR) THEN
                EXIT FOR
            END IF
        END FOR
    END IF

    IF tearDownSuiteFn IS NOT NULL THEN
        LET fixtureErr = callFixture(tearDownSuiteFn)
        IF fixtureErr IS NOT NULL THEN
            CALL recordFixtureError("(tearDownSuite)", fixtureErr, startDt)
            LET errored = errored + 1
        END IF
    END IF

    LET totalMs = elapsedMs(startDt)

    CALL Reporter.onSummary(passed, failed, errored, skipped, totalMs)

    IF optJunit IS NOT NULL AND optJunit.getLength() > 0 THEN
        CALL Reporter.writeJunit(optJunit, getSuiteName(), results)
    END IF

    IF failed > 0 OR errored > 0 THEN
        RETURN 1
    END IF

    # Nothing ran. Almost always a mistake — a mistyped --filter, a suite
    # whose registrations were never wired up — and reporting success for
    # it hands CI a green build that tested nothing.
    IF selected == 0 AND NOT optAllowEmpty THEN
        IF registry.getLength() == 0 THEN
            DISPLAY "fglunit: no tests registered "
                || "(use --allow-empty if that is intended)"
        ELSE
            DISPLAY SFMT("fglunit: --filter '%1' matched none of the %2 "
                || "registered tests (use --allow-empty if that is intended)",
                optFilter, registry.getLength())
        END IF
        RETURN 1
    END IF

    RETURN 0
END FUNCTION

PRIVATE FUNCTION matchesFilter(name STRING) RETURNS BOOLEAN
    IF optFilter IS NULL OR optFilter.getLength() == 0 THEN
        RETURN TRUE
    END IF
    RETURN name.getIndexOf(optFilter, 1) > 0
END FUNCTION

# Run a fixture, converting a raised error into a message. Returns NULL
# when the fixture completed normally.
PRIVATE FUNCTION callFixture(fn TestHandler) RETURNS STRING
    TRY
        CALL fn()
    CATCH
        RETURN SFMT("%1: %2", status, err_get(status))
    END TRY
    RETURN NULL
END FUNCTION

PRIVATE FUNCTION recordFixtureError(name STRING, message STRING,
                                    startDt DATETIME YEAR TO FRACTION(3))
    DEFINE r TestResult
    INITIALIZE r.* TO NULL
    LET r.name = name
    LET r.status = STATUS_ERROR
    LET r.message = message
    LET r.durationMs = elapsedMs(startDt)
    LET results[results.getLength() + 1].* = r.*
    CALL Reporter.onProgress(r.*)
END FUNCTION

PRIVATE FUNCTION runOne(name STRING, fn TestHandler) RETURNS TestResult
    DEFINE r TestResult
    DEFINE startDt DATETIME YEAR TO FRACTION(3)
    DEFINE errMsg, tdErr STRING

    LET r.name = name

    # Reset per-test state
    LET failureSeen = FALSE
    LET skipSeen = FALSE
    LET failureMsg = NULL
    LET failureLoc = NULL
    LET skipMsg = NULL

    LET startDt = CURRENT YEAR TO FRACTION(3)

    TRY
        IF setUpFn IS NOT NULL THEN
            CALL setUpFn()
        END IF
        CALL fn()
    CATCH
        # Unexpected runtime error escaped the test.
        # Stack is already unwound — err_get(status) carries the line.
        LET errMsg = SFMT("%1: %2", status, err_get(status))
    END TRY

    # tearDown runs whatever the body did. It is exactly when the body
    # blew up that the cleanup matters — leaving a connection open or a
    # temp table behind leaks into every later test. (JUnit's @After runs
    # unconditionally too.) A tearDown that raises is itself an error,
    # but never masks the original one.
    IF tearDownFn IS NOT NULL THEN
        LET tdErr = callFixture(tearDownFn)
        IF tdErr IS NOT NULL AND errMsg IS NULL THEN
            LET errMsg = SFMT("tearDown raised %1", tdErr)
        END IF
    END IF

    LET r.durationMs = elapsedMs(startDt)

    IF errMsg IS NOT NULL THEN
        LET r.status = STATUS_ERROR
        LET r.message = errMsg
        RETURN r
    END IF

    # A failure outranks a skip. skip() cannot abort the test — BDL gives
    # us no way to unwind — so code after it still runs; if an assertion
    # in that code failed, reporting SKIP would bury a real result.
    IF failureSeen THEN
        LET r.status = STATUS_FAIL
        LET r.message = failureMsg
        LET r.location = failureLoc
        RETURN r
    END IF

    IF skipSeen THEN
        LET r.status = STATUS_SKIP
        LET r.message = NVL(skipMsg, "skipped")
        RETURN r
    END IF

    LET r.status = STATUS_PASS
    RETURN r
END FUNCTION

# Cases and fuzz targets ---------------------------------------------

# Run one registration. A plain test goes straight to runOne; a case runs
# through the runCase trampoline and has its row added to a failure; a fuzz
# target runs many times.
PRIVATE FUNCTION runEntry(reg Registration) RETURNS TestResult
   VAR r TestResult
   CASE reg.kind
      WHEN cKindFuzz
         CALL runFuzz(reg.*) RETURNING r.*
      WHEN cKindCase
         LET activeArgFn = reg.argFn
         LET activeArgs = reg.args
         CALL runOne(reg.name, reg.fn) RETURNING r.*
         IF r.status == STATUS_FAIL OR r.status == STATUS_ERROR THEN
            LET r.message = SFMT("case %1\n%2", reg.args, NVL(r.message, ""))
         END IF
      WHEN cKindBadRow
         LET activeArgs = reg.args
         CALL runOne(reg.name, reg.fn) RETURNING r.*
      OTHERWISE
         CALL runOne(reg.name, reg.fn) RETURNING r.*
   END CASE
   RETURN r
END FUNCTION

# The TestHandler every case runs as: it hands the current row to the
# test's CaseHandler.
PRIVATE FUNCTION runCase() RETURNS ()
   VAR row util.JSONObject
   LET row = util.JSONObject.parse(activeArgs)
   CALL activeArgFn(row)
END FUNCTION

PRIVATE FUNCTION emptyCases() RETURNS ()
   CALL notifyFailure("registerCases: the table has no rows, so nothing was tested", NULL)
END FUNCTION

# The TestHandler of a row that is not a record: it fails with the message
# registerCases prepared.
PRIVATE FUNCTION notARecord() RETURNS ()
   CALL notifyFailure(activeArgs, NULL)
END FUNCTION

# Run a fuzz target: one seed per run, stop at the first failure and shrink
# it. A pass is one PASS result; a failure is one FAIL or ERROR result whose
# message carries everything needed to replay it.
PRIVATE FUNCTION runFuzz(reg Registration) RETURNS TestResult
   VAR r TestResult
   VAR best TestResult
   VAR runs INTEGER
   VAR size INTEGER
   VAR i INTEGER
   VAR failedRun INTEGER = 0
   VAR failSeed INTEGER
   VAR bestSize INTEGER
   VAR bestTrace STRING
   VAR sizeText STRING
   VAR totalMs INTEGER
   VAR skippedRuns INTEGER = 0
   VAR skipNote STRING
   VAR others STRING
   VAR nameWord STRING
   VAR nameExact BOOLEAN

   LET runs = NVL(reg.runs, cDefaultFuzzRuns)
   IF optFuzzRunsSet THEN
      LET runs = optFuzzRuns
   END IF
   LET size = Fuzz.cFullSize
   IF optFuzzSizeSet THEN
      LET size = optFuzzSize
   END IF
   LET r.name = reg.name

   IF runs <= 0 THEN
      LET r.status = STATUS_SKIP
      LET r.message = "fuzzing disabled (0 runs)"
      RETURN r
   END IF

   FOR i = 1 TO runs
      LET failSeed = Fuzz.begin(fuzzBase + i - 1, size)
      CALL runOne(reg.name, reg.fn) RETURNING r.*
      LET totalMs = totalMs + r.durationMs
      # skip() discards the input of this run, as "assume" does elsewhere:
      # it is not a failure and it does not end the target. Stopping here
      # would silently drop every later run.
      IF r.status == STATUS_SKIP THEN
         LET skippedRuns = skippedRuns + 1
         LET skipNote = r.message
         CONTINUE FOR
      END IF
      IF r.status != STATUS_PASS THEN
         LET failedRun = i
         EXIT FOR
      END IF
   END FOR

   LET r.durationMs = totalMs
   IF failedRun == 0 THEN
      # No run failed. The target passed if any run was actually tested, and
      # is reported as skipped only when every run discarded its input. A
      # pass that discarded some inputs says how many were tested: a
      # generator or precondition that quietly stops producing usable input
      # must not look like a full run.
      IF skippedRuns == runs THEN
         LET r.status = STATUS_SKIP
         LET r.message = SFMT("all %1 runs were skipped (%2)", runs, NVL(skipNote, "skipped"))
      ELSE
         LET r.status = STATUS_PASS
         LET r.location = NULL
         IF skippedRuns > 0 THEN
            LET r.message = SFMT("%1 of %2 runs tested, %3 skipped",
               runs - skippedRuns, runs, skippedRuns)
         ELSE
            LET r.message = NULL
         END IF
      END IF
      RETURN r
   END IF

   # An explicit --fuzz-size is a replay (or a deliberate limit): report the
   # failure exactly as it happens at that size, without shrinking it again.
   IF optFuzzSizeSet THEN
      LET best.* = r.*
      LET bestSize = size
      LET bestTrace = Fuzz.getTrace()
      LET sizeText = SFMT("%1", bestSize)
   ELSE
      CALL shrinkFuzz(reg.*, failSeed, size, r.*, Fuzz.getTrace())
         RETURNING best.*, bestSize, bestTrace
      LET sizeText = SFMT("%1 (shrunk from %2)", bestSize, size)
   END IF
   LET best.durationMs = totalMs
   LET others = alsoSelected(reg.name)
   IF others IS NOT NULL THEN
      LET others = SFMT("  note:   --filter is a substring match and also selects %1\n", others)
   ELSE
      LET others = ""
   END IF
   # The name is quoted for the shell the line will be pasted into. Where it
   # cannot be quoted safely the line carries the placeholder NAME and says so.
   CALL Internal.shellWord(reg.name, os.Path.pathSeparator() == ";")
      RETURNING nameWord, nameExact
   IF NOT nameExact THEN
      LET others = SFMT("  note:   replace NAME with the test name above, quoted for your shell: "
         || "it has a character that cannot be quoted safely for cmd.exe\n%1", others)
   END IF
   LET best.message = SFMT("fuzz: failed on run %1 of %2\n"
      || "  seed:   %3\n"
      || "  size:   %4\n"
      || "  inputs: %5\n"
      || "  replay: --filter %6 --seed %3 --fuzz-size %7 --fuzz-runs 1\n%9%8",
      failedRun, runs, failSeed, sizeText, NVL(bestTrace, "(none drawn)"),
      nameWord, bestSize, NVL(best.message, ""), others)
   RETURN best
END FUNCTION

#+ The other registered tests that --filter <name> would also select, as a
#+ short list, or NULL when the name selects only itself. --filter is a
#+ substring match, so the replay of "bad" also runs "badder".
PRIVATE FUNCTION alsoSelected(name STRING) RETURNS STRING
   VAR i INTEGER
   VAR shown INTEGER = 0
   VAR more INTEGER = 0
   VAR list STRING
   FOR i = 1 TO registry.getLength()
      IF registry[i].name != name AND registry[i].name.getIndexOf(name, 1) > 0 THEN
         IF shown < 3 THEN
            LET shown = shown + 1
            IF list IS NULL THEN
               LET list = registry[i].name
            ELSE
               LET list = list || ", " || registry[i].name
            END IF
         ELSE
            LET more = more + 1
         END IF
      END IF
   END FOR
   IF more > 0 THEN
      LET list = list || SFMT(" and %1 more", more)
   END IF
   RETURN list
END FUNCTION

# Re-run the failing seed at smaller sizes and keep the smallest size that
# still fails. Size 0 is tried first (the smallest input of all), then the
# range between the largest size known to pass and the smallest known to
# fail is halved. The shrink is a heuristic: generators draw fewer and
# smaller values at a smaller size, but the failure is not guaranteed to
# be monotonic in size, so what is reported is a local minimum.
PRIVATE FUNCTION shrinkFuzz(reg Registration, failSeed INTEGER, failSize INTEGER,
      found TestResult, foundTrace STRING) RETURNS (TestResult, INTEGER, STRING)
   VAR best TestResult
   VAR trial TestResult
   VAR bestSize INTEGER
   VAR bestTrace STRING
   VAR passSize INTEGER
   VAR mid INTEGER
   VAR used INTEGER

   LET best.* = found.*
   LET bestSize = failSize
   LET bestTrace = foundTrace
   LET passSize = -1

   WHILE bestSize - passSize > 1
      IF passSize < 0 THEN
         LET mid = 0
      ELSE
         LET mid = (passSize + bestSize - (passSize + bestSize) MOD 2) / 2
      END IF
      LET used = Fuzz.begin(failSeed, mid)
      CALL runOne(reg.name, reg.fn) RETURNING trial.*
      IF trial.status == STATUS_FAIL OR trial.status == STATUS_ERROR THEN
         LET best.* = trial.*
         LET bestSize = mid
         LET bestTrace = Fuzz.getTrace()
      ELSE
         LET passSize = mid
      END IF
   END WHILE
   RETURN best.*, bestSize, bestTrace
END FUNCTION

# The base seed of this run: --seed when given, otherwise from the clock
# and the process id. Printed by run(), so any failure can be replayed.
PRIVATE FUNCTION chooseFuzzBase() RETURNS BIGINT
   VAR now DATETIME HOUR TO FRACTION(3)
   VAR text STRING
   VAR buffer base.StringBuffer
   VAR stamp BIGINT
   VAR i INTEGER
   IF optFuzzSeedSet THEN
      RETURN optFuzzSeed
   END IF
   LET now = CURRENT HOUR TO FRACTION(3)
   LET text = now
   # Keep the digits of "14:22:33.113". (replaceAll with an empty
   # replacement would give NULL: an empty string is NULL in BDL.)
   LET buffer = base.StringBuffer.create()
   FOR i = 1 TO text.getLength()
      IF text.subString(i, i) >= "0" AND text.subString(i, i) <= "9" THEN
         CALL buffer.append(text.subString(i, i))
      END IF
   END FOR
   LET stamp = buffer.toString()
   RETURN stamp + fgl_getpid() MOD 1000
END FUNCTION

# How many of the selected registrations are fuzz targets that will run.
PRIVATE FUNCTION countFuzz() RETURNS INTEGER
   VAR i INTEGER
   VAR n INTEGER
   IF optFuzzRunsSet AND optFuzzRuns <= 0 THEN
      RETURN 0
   END IF
   FOR i = 1 TO registry.getLength()
      IF registry[i].kind == cKindFuzz AND matchesFilter(registry[i].name) THEN
         LET n = n + 1
      END IF
   END FOR
   RETURN n
END FUNCTION

# Accessors for Reporter (step 4) -----------------------------------

PUBLIC FUNCTION getResults() RETURNS DYNAMIC ARRAY OF TestResult
    RETURN results
END FUNCTION

PUBLIC FUNCTION getSuiteName() RETURNS STRING
    IF suiteName IS NULL OR suiteName.getLength() == 0 THEN
        RETURN "fglunit"
    END IF
    RETURN suiteName
END FUNCTION

# Helpers -----------------------------------------------------------

# Elapsed milliseconds since startDt. Computed from the INTERVAL
# t1 - t0 by string-parsing "SSSSSSSSS.FFF" — BDL has no direct
# INTERVAL→INTEGER cast, and a shell tool is explicitly off limits.
PRIVATE FUNCTION elapsedMs(startDt DATETIME YEAR TO FRACTION(3)) RETURNS INTEGER
    DEFINE nowDt DATETIME YEAR TO FRACTION(3)
    DEFINE diff INTERVAL SECOND(9) TO FRACTION(3)
    DEFINE s STRING
    DEFINE dot INTEGER
    DEFINE secs, frac INTEGER

    LET nowDt = CURRENT YEAR TO FRACTION(3)
    LET diff = nowDt - startDt
    LET s = diff
    IF s IS NULL THEN RETURN 0 END IF

    LET dot = s.getIndexOf(".", 1)
    IF dot == 0 THEN
        RETURN s * 1000
    END IF
    LET secs = s.subString(1, dot - 1)
    LET frac = s.subString(dot + 1, s.getLength())
    RETURN secs * 1000 + frac
END FUNCTION

