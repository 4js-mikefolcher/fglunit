PACKAGE com.fourjs.fglunit

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Internal

# Reporter — converts in-memory TestResult arrays into:
#   - colored plain-text progress + summary (onProgress / onSummary)
#   - JUnit XML for CI consumption (writeJunit)
#
# Colour, XML escaping and the text helpers live in Internal, shared
# with Aggregator and the two tools. See Internal.useColor for what
# "auto" can and cannot detect.

# Progress printing ------------------------------------------------

PUBLIC FUNCTION onProgress(r FglUnit.TestResult)
    DEFINE sym, color, mode STRING

    LET mode = FglUnit.getColorMode()

    CASE r.status
        WHEN FglUnit.STATUS_PASS
            LET sym = "v"
            LET color = Internal.ANSI_GREEN
        WHEN FglUnit.STATUS_FAIL
            LET sym = "x"
            LET color = Internal.ANSI_RED
        WHEN FglUnit.STATUS_ERROR
            LET sym = "E"
            LET color = Internal.ANSI_RED
        WHEN FglUnit.STATUS_SKIP
            LET sym = "-"
            LET color = Internal.ANSI_YELLOW
        OTHERWISE
            LET sym = "?"
            LET color = Internal.ANSI_YELLOW
    END CASE

    IF FglUnit.getVerbose() THEN
        DISPLAY SFMT("  %1 %2 (%3 ms)",
            Internal.colorize(mode, color, sym), r.name, r.durationMs)
        CALL printDetail(mode, r.*)
    ELSE
        DISPLAY SFMT("  %1 %2", Internal.colorize(mode, color, sym), r.name)
        # A pass with a message is a pass with something to say: a fuzz
        # target that discarded some of its inputs reports how many.
        IF r.status == FglUnit.STATUS_FAIL OR r.status == FglUnit.STATUS_ERROR
                OR (r.status == FglUnit.STATUS_PASS AND r.message IS NOT NULL) THEN
            CALL printDetail(mode, r.*)
        END IF
    END IF
END FUNCTION

PRIVATE FUNCTION printDetail(mode STRING, r FglUnit.TestResult)
    IF r.message IS NOT NULL AND r.message.getLength() > 0 THEN
        CALL Internal.printIndented("      ", r.message)
    END IF
    IF r.location IS NOT NULL AND r.location.getLength() > 0 THEN
        DISPLAY SFMT("      %1",
            Internal.colorize(mode, Internal.ANSI_DIM, "at " || r.location))
    END IF
END FUNCTION

# Summary printing -------------------------------------------------

PUBLIC FUNCTION onSummary(passed INTEGER, failed INTEGER, errored INTEGER,
                          skipped INTEGER, totalMs INTEGER)
    DEFINE total INTEGER
    DEFINE color STRING

    LET total = passed + failed + errored + skipped
    IF failed > 0 OR errored > 0 THEN
        LET color = Internal.ANSI_RED
    ELSE
        LET color = Internal.ANSI_GREEN
    END IF

    DISPLAY ""
    DISPLAY Internal.colorize(FglUnit.getColorMode(), color,
        SFMT("Tests: %1  Passed: %2  Failed: %3  Errors: %4  Skipped: %5  Time: %6 ms",
            total, passed, failed, errored, skipped, totalMs))
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
        Internal.xmlAttr(suiteName), tests, failures, errors, skipped, Internal.secondsFromMs(totalMs)))

    FOR i = 1 TO tests
        CALL writeJunitCase(ch, suiteName, results[i])
    END FOR

    CALL ch.writeLine("</testsuite>")
    CALL ch.close()
END FUNCTION

PRIVATE FUNCTION writeJunitCase(ch base.Channel, suiteName STRING, r FglUnit.TestResult)
    DEFINE openTag STRING

    LET openTag = SFMT("  <testcase name=%1 classname=%2 time=\"%3\"",
        Internal.xmlAttr(r.name), Internal.xmlAttr(suiteName), Internal.secondsFromMs(r.durationMs))

    CASE r.status
        WHEN FglUnit.STATUS_PASS
            CALL ch.writeLine(openTag || "/>")
        WHEN FglUnit.STATUS_FAIL
            CALL ch.writeLine(openTag || ">")
            CALL ch.writeLine(SFMT("    <failure message=%1>%2</failure>",
                Internal.xmlAttr(Internal.firstLine(r.message)),
                Internal.xmlText(r.message || "\n" || NVL(r.location, ""))))
            CALL ch.writeLine("  </testcase>")
        WHEN FglUnit.STATUS_ERROR
            CALL ch.writeLine(openTag || ">")
            CALL ch.writeLine(SFMT("    <error message=%1>%2</error>",
                Internal.xmlAttr(Internal.firstLine(r.message)), Internal.xmlText(NVL(r.message, ""))))
            CALL ch.writeLine("  </testcase>")
        WHEN FglUnit.STATUS_SKIP
            CALL ch.writeLine(openTag || ">")
            CALL ch.writeLine(SFMT("    <skipped message=%1/>",
                Internal.xmlAttr(NVL(r.message, ""))))
            CALL ch.writeLine("  </testcase>")
    END CASE
END FUNCTION
