PACKAGE com.fourjs.fglunit

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT util

# Assertions module.
#
# All assertions stringify (or pre-convert) their arguments and compare.
# On failure, they call captureCaller() to extract the test's file:line
# from base.Application.getStackTrace() BEFORE returning — the stack is
# still intact at this point. The captured location is reported alongside
# the failure message via FglUnit.notifyFailure().
#
# First failure wins (JUnit convention). Subsequent assertions in the
# same test still execute (and still produce output), but only the
# first is recorded against the test.

PRIVATE CONSTANT STACK_DEPTH_CALLER = 2

# Public assertions -------------------------------------------------

PUBLIC FUNCTION assertTrue(cond BOOLEAN, msg STRING)
    IF NOT cond THEN
        CALL failWith(SFMT("assertTrue failed: %1", NVL(msg, "")))
    END IF
END FUNCTION

PUBLIC FUNCTION assertFalse(cond BOOLEAN, msg STRING)
    IF cond THEN
        CALL failWith(SFMT("assertFalse failed: %1", NVL(msg, "")))
    END IF
END FUNCTION

PUBLIC FUNCTION assertEquals(expected STRING, actual STRING, msg STRING)
    IF NOT stringEquals(expected, actual) THEN
        CALL failWith(SFMT("assertEquals failed: %1\n  expected: <%2>\n  actual:   <%3>",
            NVL(msg, ""), NVL(expected, "NULL"), NVL(actual, "NULL")))
    END IF
END FUNCTION

PUBLIC FUNCTION assertNotEquals(a STRING, b STRING, msg STRING)
    IF stringEquals(a, b) THEN
        CALL failWith(SFMT("assertNotEquals failed: %1\n  both values were: <%2>",
            NVL(msg, ""), NVL(a, "NULL")))
    END IF
END FUNCTION

PUBLIC FUNCTION assertEqualsInt(expected INTEGER, actual INTEGER, msg STRING)
    IF expected != actual THEN
        CALL failWith(SFMT("assertEqualsInt failed: %1\n  expected: %2\n  actual:   %3",
            NVL(msg, ""), expected, actual))
    END IF
END FUNCTION

PUBLIC FUNCTION assertEqualsDec(expected DECIMAL(32,10), actual DECIMAL(32,10),
                                tolerance DECIMAL(32,10), msg STRING)
    DEFINE diff DECIMAL(32,10)
    LET diff = expected - actual
    IF diff < 0 THEN LET diff = -diff END IF
    IF diff > tolerance THEN
        CALL failWith(SFMT("assertEqualsDec failed: %1\n  expected: %2\n  actual:   %3\n  tolerance: %4",
            NVL(msg, ""), expected, actual, tolerance))
    END IF
END FUNCTION

PUBLIC FUNCTION assertNull(value STRING, msg STRING)
    IF value IS NOT NULL THEN
        CALL failWith(SFMT("assertNull failed: %1\n  value was: <%2>",
            NVL(msg, ""), value))
    END IF
END FUNCTION

PUBLIC FUNCTION assertNotNull(value STRING, msg STRING)
    IF value IS NULL THEN
        CALL failWith(SFMT("assertNotNull failed: %1", NVL(msg, "")))
    END IF
END FUNCTION

PUBLIC FUNCTION assertContains(haystack STRING, needle STRING, msg STRING)
    IF haystack IS NULL OR needle IS NULL
       OR haystack.getIndexOf(needle, 1) == 0 THEN
        CALL failWith(SFMT("assertContains failed: %1\n  haystack: <%2>\n  needle:   <%3>",
            NVL(msg, ""), NVL(haystack, "NULL"), NVL(needle, "NULL")))
    END IF
END FUNCTION

PUBLIC FUNCTION assertNotContains(haystack STRING, needle STRING, msg STRING)
    IF haystack IS NOT NULL AND needle IS NOT NULL
       AND haystack.getIndexOf(needle, 1) > 0 THEN
        CALL failWith(SFMT("assertNotContains failed: %1\n  haystack: <%2>\n  needle:   <%3>",
            NVL(msg, ""), haystack, needle))
    END IF
END FUNCTION

PUBLIC FUNCTION assertMatches(value STRING, regex STRING, msg STRING)
    DEFINE re util.Regexp
    TRY
        LET re = util.Regexp.compile(regex)
    CATCH
        CALL failWith(SFMT("assertMatches: invalid regex <%1> (%2)",
            NVL(regex, "NULL"), err_get(status)))
        RETURN
    END TRY
    IF value IS NULL OR NOT re.matches(value) THEN
        CALL failWith(SFMT("assertMatches failed: %1\n  value: <%2>\n  regex: <%3>",
            NVL(msg, ""), NVL(value, "NULL"), NVL(regex, "NULL")))
    END IF
END FUNCTION

PUBLIC FUNCTION assertThrows(fn FglUnit.TestHandler, msg STRING)
    # The function `fn` must use `WHENEVER ANY ERROR RAISE` for any
    # runtime error to propagate up into our TRY/CATCH. BDL's default
    # error policy silently absorbs expression errors in called
    # functions, so without RAISE the error never reaches us.
    # See USERGUIDE.md "Testing error paths" for the idiom.
    DEFINE threw BOOLEAN
    LET threw = FALSE
    TRY
        CALL fn()
    CATCH
        LET threw = TRUE
    END TRY
    IF NOT threw THEN
        CALL failWith(SFMT("assertThrows failed: %1\n  no error was raised",
            NVL(msg, "")))
    END IF
END FUNCTION

PUBLIC FUNCTION fail(msg STRING)
    CALL failWith(SFMT("fail(): %1", NVL(msg, "")))
END FUNCTION

PUBLIC FUNCTION skip(msg STRING)
    CALL FglUnit.notifySkip(NVL(msg, "skipped"))
END FUNCTION

# Private helpers ---------------------------------------------------

# Bridge to FglUnit.notifyFailure. Separated out so every assertion
# funnels through one captureCaller() call at the same stack depth.
PRIVATE FUNCTION failWith(message STRING)
    DEFINE location STRING
    LET location = captureCaller(STACK_DEPTH_CALLER)
    CALL FglUnit.notifyFailure(message, location)
END FUNCTION

# captureCaller(depth) returns the stack frame at the requested depth,
# counted from the *caller of this helper*.
#
#   depth=0 -> failWith             (our immediate caller)
#   depth=1 -> assertTrue/Equals/.. (the assertion itself)
#   depth=2 -> test_*               (the test function — what we want)
#
# base.Application.getStackTrace() output format:
#   #0 captureCaller()   at Assertions.4gl:NNN
#   #1 failWith()        at Assertions.4gl:NNN
#   #2 assertTrue()      at Assertions.4gl:NNN
#   #3 test_addition()   at my_tests.4gl:42     <-- depth 2 in our numbering
#   ...
# So we want line index (depth + 2) in the trace, 1-based.
PRIVATE FUNCTION captureCaller(depth INTEGER) RETURNS STRING
    DEFINE trace STRING
    DEFINE tok base.StringTokenizer
    DEFINE line STRING
    DEFINE idx, target INTEGER

    LET trace = base.Application.getStackTrace()
    IF trace IS NULL THEN RETURN "" END IF

    LET target = depth + 2
    LET tok = base.StringTokenizer.create(trace, "\n")
    LET idx = 0
    WHILE tok.hasMoreTokens()
        LET idx = idx + 1
        LET line = tok.nextToken()
        IF idx = target THEN
            RETURN line.trim()
        END IF
    END WHILE
    RETURN ""
END FUNCTION

# STRING equality that treats NULL as equal to NULL.
PRIVATE FUNCTION stringEquals(a STRING, b STRING) RETURNS BOOLEAN
    IF a IS NULL AND b IS NULL THEN RETURN TRUE END IF
    IF a IS NULL OR b IS NULL THEN RETURN FALSE END IF
    RETURN a = b
END FUNCTION
