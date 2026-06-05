PACKAGE com.fourjs.fglunit

# fglunit-run — run many compiled test suites and aggregate one report.
#
# Each child is a normal fglunit program (a .42m). The driver runs it with
# --junit pointed at a temp file, reads that JUnit XML back, and merges all
# suites into one <testsuites> document + a combined console summary + a
# combined exit code. A child that crashes (no/garbage XML, abnormal exit)
# is reported as an errored suite rather than silently dropped.
#
# From an installed package:  fglpkg bdl fglunit fglunit_run [options] <prog>...
# In-repo / from a build:     fglrun fglunit_run.42m [options] <prog>...
#     --dir <d>       run every *.run.42m under <d> (non-recursive)
#     --junit <file>  write the aggregated <testsuites> XML
#     --filter <pat>  passed through to each child suite
#     --fail-fast     stop after the first failing suite
#     -v, --verbose   passed through; also echoes each child's console
#     --color <mode>  auto (default) | always | never
#     -h, --help

IMPORT os
IMPORT FGL com.fourjs.fglunit.Aggregator

PRIVATE CONSTANT ANSI_RESET = "\x1b[0m"
PRIVATE CONSTANT ANSI_GREEN = "\x1b[32m"
PRIVATE CONSTANT ANSI_RED   = "\x1b[31m"

PRIVATE DEFINE progs DYNAMIC ARRAY OF STRING
PRIVATE DEFINE optJunit, optFilter STRING
PRIVATE DEFINE optColor STRING
PRIVATE DEFINE optVerbose, optFailFast BOOLEAN
PRIVATE DEFINE origLdPath STRING   # FGLLDPATH as inherited, restored per child

MAIN
    DEFINE summaries DYNAMIC ARRAY OF Aggregator.SuiteSummary
    DEFINE s Aggregator.SuiteSummary
    DEFINE t Aggregator.Totals
    DEFINE i INTEGER
    DEFINE suiteFailed, stoppedEarly BOOLEAN

    LET optColor = "auto"
    LET origLdPath = fgl_getenv("FGLLDPATH")
    CALL parseArgs()

    IF progs.getLength() == 0 THEN
        DISPLAY "fglunit-run: no programs (use --dir or pass <program>.42m)"
        CALL usage()
        EXIT PROGRAM 2
    END IF

    FOR i = 1 TO progs.getLength()
        LET s = runOne(progs[i], i)
        LET summaries[summaries.getLength() + 1].* = s.*
        CALL printProgress(s)
        LET suiteFailed = (s.failures > 0 OR s.errors > 0)
        IF optFailFast AND suiteFailed THEN
            LET stoppedEarly = TRUE
            EXIT FOR
        END IF
    END FOR

    LET t = Aggregator.totals(summaries)
    CALL printSummary(t, stoppedEarly)

    IF optJunit IS NOT NULL AND optJunit.getLength() > 0 THEN
        IF NOT writeFile(optJunit, Aggregator.renderSuites(summaries)) THEN
            DISPLAY SFMT("fglunit-run: cannot write aggregated JUnit '%1'", optJunit)
            EXIT PROGRAM 2
        END IF
    END IF

    IF t.failures > 0 OR t.errors > 0 THEN
        EXIT PROGRAM 1
    END IF
    EXIT PROGRAM 0
END MAIN

# Run one child program and return its (possibly synthesized) summary.
PRIVATE FUNCTION runOne(prog STRING, idx INTEGER) RETURNS Aggregator.SuiteSummary
    DEFINE xmlPath, cmd, xmlText, console STRING
    DEFINE s Aggregator.SuiteSummary

    LET xmlPath = tempPath(idx, "xml")
    LET cmd = buildCmd(prog, xmlPath)

    # fglrun does not consult FGLLDPATH to locate the child's MAIN module,
    # but it does for the module's IMPORTs — so put the program's own
    # directory on FGLLDPATH (ahead of what we inherited) before launching.
    # Set via fgl_setenv (inherited by the child) rather than a shell-
    # specific "VAR=val cmd" prefix, so this stays OS-agnostic.
    CALL fgl_setenv("FGLLDPATH", childLdPath(prog))
    LET console = runCapture(cmd)
    CALL fgl_setenv("FGLLDPATH", NVL(origLdPath, ""))

    LET xmlText = readFile(xmlPath)
    LET s = Aggregator.parseSuiteXml(xmlText)
    IF NOT s.valid THEN
        # No usable JUnit => the child crashed or never started. Detected by
        # the absent/invalid file, not by an OS-specific exit-status code.
        LET s = Aggregator.crashedSuite(stem(os.Path.baseName(prog)),
            SFMT("child '%1' produced no usable JUnit output\n%2",
                prog, NVL(tailOf(console), "")))
    END IF

    IF optVerbose AND console IS NOT NULL AND console.getLength() > 0 THEN
        CALL printIndented("    ", console)
    END IF

    CALL deleteFile(xmlPath)
    RETURN s
END FUNCTION

# fglrun "<prog>" --junit "<xml>" --color never [opts] 2>&1
# Quoting and "2>&1" are valid on both POSIX shells and Windows cmd.exe.
PRIVATE FUNCTION buildCmd(prog STRING, xmlPath STRING) RETURNS STRING
    DEFINE sb base.StringBuffer
    LET sb = base.StringBuffer.create()
    CALL sb.append(SFMT("fglrun \"%1\" --junit \"%2\" --color never", prog, xmlPath))
    IF optFilter IS NOT NULL AND optFilter.getLength() > 0 THEN
        CALL sb.append(SFMT(" --filter \"%1\"", optFilter))
    END IF
    IF optVerbose THEN
        CALL sb.append(" -v")
    END IF
    CALL sb.append(" 2>&1")   # merge stderr so the pipe captures it too
    RETURN sb.toString()
END FUNCTION

# Run a command and capture its combined output. openPipe avoids shell
# redirection operators and temp log files.
PRIVATE FUNCTION runCapture(cmd STRING) RETURNS STRING
    DEFINE ch base.Channel
    DEFINE sb base.StringBuffer
    DEFINE line STRING
    LET ch = base.Channel.create()
    TRY
        CALL ch.openPipe(cmd, "r")
    CATCH
        RETURN NULL
    END TRY
    LET sb = base.StringBuffer.create()
    WHILE TRUE
        LET line = ch.readLine()
        IF ch.isEof() THEN EXIT WHILE END IF
        CALL sb.append(line)
        CALL sb.append("\n")
    END WHILE
    CALL ch.close()
    RETURN sb.toString()
END FUNCTION

# The program's own directory, prepended to the inherited FGLLDPATH using
# the OS path-list separator (":" on Unix, ";" on Windows).
PRIVATE FUNCTION childLdPath(prog STRING) RETURNS STRING
    DEFINE dir STRING
    LET dir = os.Path.dirName(prog)
    IF dir IS NULL OR dir.getLength() == 0 THEN
        RETURN NVL(origLdPath, "")
    END IF
    IF origLdPath IS NULL OR origLdPath.getLength() == 0 THEN
        RETURN dir
    END IF
    RETURN dir || os.Path.pathSeparator() || origLdPath
END FUNCTION

# Output ------------------------------------------------------------

PRIVATE FUNCTION printProgress(s Aggregator.SuiteSummary)
    DEFINE color, sym STRING
    IF s.failures > 0 OR s.errors > 0 THEN
        LET color = ANSI_RED LET sym = "x"
    ELSE
        LET color = ANSI_GREEN LET sym = "v"
    END IF
    DISPLAY SFMT("  %1%2%3 %4: %5 tests, %6 failed, %7 errors, %8 skipped (%9 s)",
        on(color), sym, off(),
        s.name, s.tests, s.failures, s.errors, s.skipped, NVL(s.timeSec, "0"))
END FUNCTION

PRIVATE FUNCTION printSummary(t Aggregator.Totals, stoppedEarly BOOLEAN)
    DEFINE color STRING
    DEFINE passed INTEGER
    LET passed = t.tests - t.failures - t.errors - t.skipped
    IF t.failures > 0 OR t.errors > 0 THEN
        LET color = ANSI_RED
    ELSE
        LET color = ANSI_GREEN
    END IF
    DISPLAY ""
    IF stoppedEarly THEN
        DISPLAY "(stopped early — --fail-fast)"
    END IF
    DISPLAY SFMT("%1Suites: %2  Tests: %3  Passed: %4  Failed: %5  Errors: %6  Skipped: %7%8",
        on(color), t.suites, t.tests, passed, t.failures, t.errors, t.skipped, off())
END FUNCTION

PRIVATE FUNCTION printIndented(indent STRING, body STRING)
    DEFINE tok base.StringTokenizer
    LET tok = base.StringTokenizer.create(body, "\n")
    WHILE tok.hasMoreTokens()
        DISPLAY indent, tok.nextToken()
    END WHILE
END FUNCTION

# Args --------------------------------------------------------------

PRIVATE FUNCTION parseArgs()
    DEFINE i, n INTEGER
    DEFINE arg STRING
    LET n = num_args()
    LET i = 1
    WHILE i <= n
        LET arg = arg_val(i)
        CASE
            WHEN arg == "-h" OR arg == "--help"
                CALL usage()
                EXIT PROGRAM 0
            WHEN arg == "-v" OR arg == "--verbose"
                LET optVerbose = TRUE
            WHEN arg == "--fail-fast"
                LET optFailFast = TRUE
            WHEN arg == "--junit"
                LET optJunit = needValue(arg, i, n)
                LET i = i + 1
            WHEN arg == "--filter"
                LET optFilter = needValue(arg, i, n)
                LET i = i + 1
            WHEN arg == "--color"
                LET optColor = needValue(arg, i, n)
                LET i = i + 1
                CASE optColor
                    WHEN "auto"
                    WHEN "always"
                    WHEN "never"
                    OTHERWISE
                        DISPLAY SFMT("fglunit-run: --color must be auto|always|never (got '%1')", optColor)
                        EXIT PROGRAM 2
                END CASE
            WHEN arg == "--dir"
                CALL scanDir(needValue(arg, i, n))
                LET i = i + 1
            WHEN arg.getIndexOf("-", 1) == 1
                DISPLAY SFMT("fglunit-run: unknown option '%1'", arg)
                CALL usage()
                EXIT PROGRAM 2
            OTHERWISE
                LET progs[progs.getLength() + 1] = arg
        END CASE
        LET i = i + 1
    END WHILE
END FUNCTION

PRIVATE FUNCTION needValue(flag STRING, i INTEGER, n INTEGER) RETURNS STRING
    IF i + 1 > n THEN
        DISPLAY SFMT("fglunit-run: option '%1' requires a value", flag)
        EXIT PROGRAM 2
    END IF
    RETURN arg_val(i + 1)
END FUNCTION

# Append every *.run.42m in `dir` (non-recursive) to the program list.
PRIVATE FUNCTION scanDir(dir STRING)
    DEFINE h INTEGER
    DEFINE name, low STRING
    LET h = os.Path.dirOpen(dir)
    IF h == 0 THEN
        DISPLAY SFMT("fglunit-run: cannot open directory '%1'", dir)
        EXIT PROGRAM 2
    END IF
    WHILE TRUE
        LET name = os.Path.dirNext(h)
        IF name IS NULL OR name == "" THEN EXIT WHILE END IF
        LET low = name.toLowerCase()
        IF endsWith(low, ".run.42m") THEN
            LET progs[progs.getLength() + 1] = os.Path.join(dir, name)
        END IF
    END WHILE
    CALL os.Path.dirClose(h)
END FUNCTION

# Helpers -----------------------------------------------------------

# A writable temp directory, probed OS-agnostically: TMPDIR (Unix) then
# TEMP / TMP (Windows), falling back to the current directory. os.Path.join
# applies the platform directory separator.
PRIVATE FUNCTION tempPath(idx INTEGER, ext STRING) RETURNS STRING
    DEFINE dir STRING
    LET dir = fgl_getenv("TMPDIR")
    IF dir IS NULL OR dir.getLength() == 0 THEN LET dir = fgl_getenv("TEMP") END IF
    IF dir IS NULL OR dir.getLength() == 0 THEN LET dir = fgl_getenv("TMP") END IF
    IF dir IS NULL OR dir.getLength() == 0 THEN LET dir = os.Path.pwd() END IF
    RETURN os.Path.join(dir, SFMT("fglunit.%1.%2.%3", fgl_getpid(), idx, ext))
END FUNCTION

PRIVATE FUNCTION tailOf(s STRING) RETURNS STRING
    IF s IS NULL THEN RETURN NULL END IF
    IF s.getLength() <= 800 THEN RETURN s END IF
    RETURN s.subString(s.getLength() - 800 + 1, s.getLength())
END FUNCTION

PRIVATE FUNCTION readFile(path STRING) RETURNS STRING
    DEFINE ch base.Channel
    DEFINE sb base.StringBuffer
    DEFINE line STRING
    LET ch = base.Channel.create()
    TRY
        CALL ch.openFile(path, "r")
    CATCH
        RETURN NULL
    END TRY
    LET sb = base.StringBuffer.create()
    WHILE TRUE
        LET line = ch.readLine()
        IF ch.isEof() THEN EXIT WHILE END IF
        CALL sb.append(line)
        CALL sb.append("\n")
    END WHILE
    CALL ch.close()
    RETURN sb.toString()
END FUNCTION

PRIVATE FUNCTION writeFile(path STRING, text STRING) RETURNS BOOLEAN
    DEFINE ch base.Channel
    LET ch = base.Channel.create()
    TRY
        CALL ch.openFile(path, "w")
    CATCH
        RETURN FALSE
    END TRY
    IF text.getCharAt(text.getLength()) == "\n" THEN
        LET text = text.subString(1, text.getLength() - 1)
    END IF
    CALL ch.writeLine(text)
    CALL ch.close()
    RETURN TRUE
END FUNCTION

PRIVATE FUNCTION deleteFile(path STRING)
    DEFINE res INTEGER
    TRY
        LET res = os.Path.delete(path)
    CATCH
    END TRY
END FUNCTION

PRIVATE FUNCTION stem(fileName STRING) RETURNS STRING
    DEFINE dot INTEGER
    LET dot = fileName.getIndexOf(".", 1)
    IF dot > 1 THEN RETURN fileName.subString(1, dot - 1) END IF
    RETURN fileName
END FUNCTION

PRIVATE FUNCTION endsWith(s STRING, suffix STRING) RETURNS BOOLEAN
    DEFINE at INTEGER
    IF s.getLength() < suffix.getLength() THEN RETURN FALSE END IF
    LET at = s.getLength() - suffix.getLength() + 1
    RETURN s.subString(at, s.getLength()) == suffix
END FUNCTION

# Color -------------------------------------------------------------

PRIVATE FUNCTION on(code STRING) RETURNS STRING
    IF useColor() THEN RETURN code END IF
    RETURN ""
END FUNCTION

PRIVATE FUNCTION off() RETURNS STRING
    IF useColor() THEN RETURN ANSI_RESET END IF
    RETURN ""
END FUNCTION

PRIVATE FUNCTION useColor() RETURNS BOOLEAN
    DEFINE term STRING
    CASE optColor
        WHEN "always" RETURN TRUE
        WHEN "never"  RETURN FALSE
    END CASE
    LET term = fgl_getenv("TERM")
    IF term IS NULL OR term.getLength() == 0 OR term == "dumb" THEN
        RETURN FALSE
    END IF
    RETURN TRUE
END FUNCTION

PRIVATE FUNCTION usage()
    DISPLAY "Usage: fglrun fglunit_run.42m [options] <program.42m> ..."
    DISPLAY ""
    DISPLAY "Options:"
    DISPLAY "  --dir <d>       Run every *.run.42m under <d> (non-recursive)"
    DISPLAY "  --junit <file>  Write the aggregated <testsuites> XML"
    DISPLAY "  --filter <pat>  Passed through to each child suite"
    DISPLAY "  --fail-fast     Stop after the first failing suite"
    DISPLAY "  -v, --verbose   Echo each child's console output"
    DISPLAY "  --color <mode>  auto (default) | always | never"
    DISPLAY "  -h, --help      Show this help"
    DISPLAY ""
    DISPLAY "Exit code: 0 when all suites pass, 1 otherwise."
END FUNCTION
