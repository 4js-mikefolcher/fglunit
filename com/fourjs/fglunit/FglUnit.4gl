PACKAGE com.fourjs.fglunit

IMPORT FGL com.fourjs.fglunit.Reporter

# Public types -------------------------------------------------------

PUBLIC TYPE TestHandler FUNCTION() RETURNS ()

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

PRIVATE TYPE Registration RECORD
    name STRING,
    fn TestHandler
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

# Public API: options (usually set by CliArgs) ----------------------

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

            CALL runOne(registry[i].name, registry[i].fn) RETURNING r.*
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

