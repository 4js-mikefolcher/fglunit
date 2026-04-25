PACKAGE com.fourjs.fglunit

IMPORT FGL com.fourjs.fglunit.FglUnit

# Reporter — converts in-memory TestResult arrays into:
#   - colored plain-text progress + summary (onProgress / onSummary)
#   - JUnit XML for CI consumption (writeJunit)
#
# ANSI color usage follows the --color flag: "always" forces on,
# "never" forces off, "auto" (default) only colors when stdout is a
# TTY. We detect TTY via the TERM env var — crude but good enough;
# CI systems typically unset or set TERM=dumb.

PRIVATE CONSTANT ANSI_RESET  = "\x1b[0m"
PRIVATE CONSTANT ANSI_GREEN  = "\x1b[32m"
PRIVATE CONSTANT ANSI_RED    = "\x1b[31m"
PRIVATE CONSTANT ANSI_YELLOW = "\x1b[33m"
PRIVATE CONSTANT ANSI_DIM    = "\x1b[2m"

# Progress printing ------------------------------------------------

PUBLIC FUNCTION onProgress(r FglUnit.TestResult)
    DEFINE sym, color STRING

    CASE r.status
        WHEN FglUnit.STATUS_PASS
            LET sym = "v"
            LET color = ANSI_GREEN
        WHEN FglUnit.STATUS_FAIL
            LET sym = "x"
            LET color = ANSI_RED
        WHEN FglUnit.STATUS_ERROR
            LET sym = "E"
            LET color = ANSI_RED
        WHEN FglUnit.STATUS_SKIP
            LET sym = "-"
            LET color = ANSI_YELLOW
    END CASE

    IF FglUnit.getVerbose() THEN
        DISPLAY SFMT("  %1%2%3 %4 (%5 ms)",
            colorOn(color), sym, colorOff(),
            r.name, r.durationMs)
        IF r.message IS NOT NULL AND r.message.getLength() > 0 THEN
            CALL printIndented("      ", r.message)
        END IF
        IF r.location IS NOT NULL AND r.location.getLength() > 0 THEN
            DISPLAY SFMT("      %1at %2%3", colorOn(ANSI_DIM), r.location, colorOff())
        END IF
    ELSE
        DISPLAY SFMT("  %1%2%3 %4",
            colorOn(color), sym, colorOff(), r.name)
        IF r.status == FglUnit.STATUS_FAIL OR r.status == FglUnit.STATUS_ERROR THEN
            IF r.message IS NOT NULL AND r.message != "" THEN
                CALL printIndented("      ", r.message)
            END IF
            IF r.location IS NOT NULL AND r.location != "" THEN
                DISPLAY SFMT("      %1at %2%3", colorOn(ANSI_DIM), r.location, colorOff())
            END IF
        END IF
    END IF
END FUNCTION

# Summary printing -------------------------------------------------

PUBLIC FUNCTION onSummary(passed INTEGER, failed INTEGER, errored INTEGER,
                          skipped INTEGER, totalMs INTEGER)
    DEFINE total INTEGER
    DEFINE color STRING

    LET total = passed + failed + errored + skipped
    IF failed > 0 OR errored > 0 THEN
        LET color = ANSI_RED
    ELSE
        LET color = ANSI_GREEN
    END IF

    DISPLAY ""
    DISPLAY SFMT("%1Tests: %2  Passed: %3  Failed: %4  Errors: %5  Skipped: %6  Time: %7 ms%8",
        colorOn(color), total, passed, failed, errored, skipped, totalMs, colorOff())
END FUNCTION

PUBLIC FUNCTION onHeader(suiteName STRING)
    IF suiteName IS NOT NULL AND suiteName.getLength() > 0 THEN
        DISPLAY suiteName
    END IF
END FUNCTION

# JUnit XML output -------------------------------------------------
# Format:
#   <testsuite name="..." tests="N" failures="F" errors="E" skipped="S" time="T">
#     <testcase name="..." time="0.001" classname="suite">
#       <failure message="...">...</failure>       <!-- on FAIL -->
#       <error message="...">...</error>           <!-- on ERROR -->
#       <skipped/>                                  <!-- on SKIP -->
#     </testcase>
#     ...
#   </testsuite>

PUBLIC FUNCTION writeJunit(path STRING, suiteName STRING,
                           results DYNAMIC ARRAY OF FglUnit.TestResult)
    DEFINE ch base.Channel
    DEFINE i INTEGER
    DEFINE tests, failures, errors, skipped INTEGER
    DEFINE totalMs INTEGER

    LET tests = results.getLength()
    FOR i = 1 TO tests
        CASE results[i].status
            WHEN FglUnit.STATUS_FAIL  LET failures = failures + 1
            WHEN FglUnit.STATUS_ERROR LET errors   = errors   + 1
            WHEN FglUnit.STATUS_SKIP  LET skipped  = skipped  + 1
        END CASE
        LET totalMs = totalMs + results[i].durationMs
    END FOR

    LET ch = base.Channel.create()
    TRY
        CALL ch.openFile(path, "w")
    CATCH
        DISPLAY SFMT("fglunit: cannot open JUnit output '%1': %2",
            path, err_get(status))
        RETURN
    END TRY

    CALL ch.writeLine("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    CALL ch.writeLine(SFMT(
        "<testsuite name=%1 tests=\"%2\" failures=\"%3\" errors=\"%4\" skipped=\"%5\" time=\"%6\">",
        xmlAttr(suiteName), tests, failures, errors, skipped, formatSeconds(totalMs)))

    FOR i = 1 TO tests
        CALL writeJunitCase(ch, suiteName, results[i])
    END FOR

    CALL ch.writeLine("</testsuite>")
    CALL ch.close()
END FUNCTION

PRIVATE FUNCTION writeJunitCase(ch base.Channel, suiteName STRING, r FglUnit.TestResult)
    DEFINE openTag STRING

    LET openTag = SFMT("  <testcase name=%1 classname=%2 time=\"%3\"",
        xmlAttr(r.name), xmlAttr(suiteName), formatSeconds(r.durationMs))

    CASE r.status
        WHEN FglUnit.STATUS_PASS
            CALL ch.writeLine(openTag || "/>")
        WHEN FglUnit.STATUS_FAIL
            CALL ch.writeLine(openTag || ">")
            CALL ch.writeLine(SFMT("    <failure message=%1>%2</failure>",
                xmlAttr(firstLine(r.message)),
                xmlText(r.message || "\n" || NVL(r.location, ""))))
            CALL ch.writeLine("  </testcase>")
        WHEN FglUnit.STATUS_ERROR
            CALL ch.writeLine(openTag || ">")
            CALL ch.writeLine(SFMT("    <error message=%1>%2</error>",
                xmlAttr(firstLine(r.message)), xmlText(NVL(r.message, ""))))
            CALL ch.writeLine("  </testcase>")
        WHEN FglUnit.STATUS_SKIP
            CALL ch.writeLine(openTag || ">")
            CALL ch.writeLine(SFMT("    <skipped message=%1/>",
                xmlAttr(NVL(r.message, ""))))
            CALL ch.writeLine("  </testcase>")
    END CASE
END FUNCTION

# Color helpers ----------------------------------------------------

PRIVATE FUNCTION colorOn(code STRING) RETURNS STRING
    IF useColor() THEN RETURN code END IF
    RETURN ""
END FUNCTION

PRIVATE FUNCTION colorOff() RETURNS STRING
    IF useColor() THEN RETURN ANSI_RESET END IF
    RETURN ""
END FUNCTION

PRIVATE FUNCTION useColor() RETURNS BOOLEAN
    DEFINE mode, term STRING

    LET mode = FglUnit.getColorMode()
    CASE mode
        WHEN "always" RETURN TRUE
        WHEN "never"  RETURN FALSE
    END CASE
    # "auto"
    LET term = fgl_getenv("TERM")
    IF term IS NULL OR term.getLength() == 0 OR term == "dumb" THEN
        RETURN FALSE
    END IF
    RETURN TRUE
END FUNCTION

# XML escaping -----------------------------------------------------

PRIVATE FUNCTION xmlAttr(v STRING) RETURNS STRING
    RETURN "\"" || xmlEscape(NVL(v, "")) || "\""
END FUNCTION

PRIVATE FUNCTION xmlText(v STRING) RETURNS STRING
    RETURN xmlEscape(NVL(v, ""))
END FUNCTION

PRIVATE FUNCTION xmlEscape(v STRING) RETURNS STRING
    # `&` MUST come first, else subsequent replacements get re-escaped.
    # replaceAll takes a regex and a replacement; `&`, `<`, `>`, `"`
    # have no regex meaning, so we can pass them literally. The
    # replacement strings also contain no `$`, so they're literal.
    LET v = v.replaceAll("&", "&amp;")
    LET v = v.replaceAll("<", "&lt;")
    LET v = v.replaceAll(">", "&gt;")
    LET v = v.replaceAll("\"", "&quot;")
    RETURN v
END FUNCTION

# Formatting helpers -----------------------------------------------

PRIVATE FUNCTION formatSeconds(ms INTEGER) RETURNS STRING
    DEFINE secs DECIMAL(18,3)
    LET secs = ms / 1000.0
    RETURN secs USING "<<<<<<<<<<<<<<<<<&.&&&"
END FUNCTION

PRIVATE FUNCTION firstLine(s STRING) RETURNS STRING
    DEFINE nl INTEGER
    IF s IS NULL THEN RETURN "" END IF
    LET nl = s.getIndexOf("\n", 1)
    IF nl == 0 THEN RETURN s END IF
    RETURN s.subString(1, nl - 1)
END FUNCTION

PRIVATE FUNCTION printIndented(indent STRING, body STRING)
    DEFINE tok base.StringTokenizer
    LET tok = base.StringTokenizer.create(body, "\n")
    WHILE tok.hasMoreTokens()
        DISPLAY indent, tok.nextToken()
    END WHILE
END FUNCTION
