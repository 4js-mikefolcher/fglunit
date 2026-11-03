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
#     --seed <n>, --fuzz-runs <n>, --fuzz-size <n>
#                     passed through (fuzz targets; digits only)
#     --fail-fast     stop after the first failing suite
#     --allow-empty   exit 0 even when no suite ran a single test
#     -v, --verbose   passed through; also echoes each child's console
#     --color <mode>  auto (default) | always | never
#     -h, --help

IMPORT os
IMPORT util
IMPORT FGL com.fourjs.fglunit.Aggregator
IMPORT FGL com.fourjs.fglunit.Internal

PRIVATE DEFINE progs DYNAMIC ARRAY OF STRING
PRIVATE DEFINE optJunit, optFilter STRING
PRIVATE DEFINE optColor STRING
PRIVATE DEFINE optSeed, optFuzzRuns, optFuzzSize STRING   # digits only
PRIVATE DEFINE optVerbose, optFailFast, optAllowEmpty BOOLEAN
PRIVATE DEFINE origLdPath STRING   # FGLLDPATH as inherited, restored per child

MAIN
    DEFINE summaries DYNAMIC ARRAY OF Aggregator.SuiteSummary
    DEFINE s Aggregator.SuiteSummary
    DEFINE t Aggregator.Totals
    DEFINE i INTEGER
    DEFINE suiteFailed, stoppedEarly BOOLEAN

    LET optColor = "auto"
    LET origLdPath = fgl_getenv("FGLLDPATH")
    CALL util.Math.srand()
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
        IF NOT Internal.writeFile(optJunit, Aggregator.renderSuites(summaries)) THEN
            DISPLAY SFMT("fglunit-run: cannot write aggregated JUnit '%1'", optJunit)
            EXIT PROGRAM 2
        END IF
    END IF

    IF t.failures > 0 OR t.errors > 0 THEN
        EXIT PROGRAM 1
    END IF

    # Every suite ran but not one test executed: a mistyped --filter, or
    # a --dir that matched programs containing nothing. Reporting success
    # would hand CI a green build over an empty run.
    IF t.tests == 0 AND NOT optAllowEmpty THEN
        DISPLAY "fglunit-run: no tests ran across "
            || t.suites || " suite(s) "
            || "(use --allow-empty if that is intended)"
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

    LET xmlText = Internal.readFile(xmlPath)
    LET s = Aggregator.parseSuiteXml(xmlText)
    IF NOT s.valid THEN
        # No usable JUnit => the child crashed or never started. Detected by
        # the absent/invalid file, not by an OS-specific exit-status code.
        LET s = Aggregator.crashedSuite(stem(os.Path.baseName(prog)),
            SFMT("child '%1' produced no usable JUnit output\n%2",
                prog, NVL(tailOf(console), "")))
    END IF

    IF optVerbose AND console IS NOT NULL AND console.getLength() > 0 THEN
        CALL Internal.printIndented("    ", console)
    END IF

    CALL Internal.deleteFile(xmlPath)
    RETURN s
END FUNCTION

# fglrun <prog> --junit <xml> --color never [opts] 2>&1
#
# openPipe() hands this string to a shell, so every interpolated value
# must be quoted by shellArg() — never embedded raw. "2>&1" is valid on
# both POSIX shells and Windows cmd.exe.
PRIVATE FUNCTION buildCmd(prog STRING, xmlPath STRING) RETURNS STRING
    DEFINE sb base.StringBuffer
    LET sb = base.StringBuffer.create()
    CALL sb.append(SFMT("fglrun %1 --junit %2 --color never",
        shellArg("program path", prog),
        shellArg("temporary file path", xmlPath)))
    IF optFilter IS NOT NULL AND optFilter.getLength() > 0 THEN
        CALL sb.append(SFMT(" --filter %1", shellArg("--filter", optFilter)))
    END IF
    # Validated as digits when parsed, so they cannot carry shell syntax.
    IF optSeed IS NOT NULL THEN
        CALL sb.append(SFMT(" --seed %1", optSeed))
    END IF
    IF optFuzzRuns IS NOT NULL THEN
        CALL sb.append(SFMT(" --fuzz-runs %1", optFuzzRuns))
    END IF
    IF optFuzzSize IS NOT NULL THEN
        CALL sb.append(SFMT(" --fuzz-size %1", optFuzzSize))
    END IF
    IF optVerbose THEN
        CALL sb.append(" -v")
    END IF
    CALL sb.append(" 2>&1")   # merge stderr so the pipe captures it too
    RETURN sb.toString()
END FUNCTION

# Quote one value for the shell that openPipe() runs the command through.
#
# Program paths and filter patterns arrive from argv, and a CI pipeline
# may well build a filter out of a branch name or a PR title. Interpolated
# raw, a value like `$(rm -rf .)` or `x"; cmd; echo "` runs as a command;
# the double quotes previously used here stop neither on a POSIX shell.
#
# POSIX: single quotes make every character literal, so an embedded single
# quote is the only way out. cmd.exe: double quotes are the only quoting
# available, and %VAR% still expands inside them. Characters that quoting
# cannot neutralize are refused rather than passed through — a test filter
# is never worth a shell escape.
PRIVATE FUNCTION shellArg(what STRING, value STRING) RETURNS STRING
    IF value IS NULL THEN LET value = "" END IF

    IF isWindows() THEN
        IF containsAnyOf(value, "\"%\n\r") THEN
            CALL rejectArg(what, value)
        END IF
        RETURN "\"" || value || "\""
    END IF

    IF containsAnyOf(value, "'\n\r") THEN
        CALL rejectArg(what, value)
    END IF
    RETURN "'" || value || "'"
END FUNCTION

PRIVATE FUNCTION rejectArg(what STRING, value STRING)
    DISPLAY SFMT("fglunit-run: refusing to run: the %1 contains a character "
                 || "that cannot be quoted safely for the shell: <%2>", what, value)
    EXIT PROGRAM 2
END FUNCTION

PRIVATE FUNCTION containsAnyOf(value STRING, chars STRING) RETURNS BOOLEAN
    DEFINE i INTEGER
    FOR i = 1 TO chars.getLength()
        IF value.getIndexOf(chars.subString(i, i), 1) > 0 THEN
            RETURN TRUE
        END IF
    END FOR
    RETURN FALSE
END FUNCTION

# ";" is the PATH-list separator on Windows only; os.Path has no direct
# platform predicate. childLdPath() already depends on this distinction.
PRIVATE FUNCTION isWindows() RETURNS BOOLEAN
    RETURN os.Path.pathSeparator() == ";"
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
        LET color = Internal.ANSI_RED LET sym = "x"
    ELSE
        LET color = Internal.ANSI_GREEN LET sym = "v"
    END IF
    DISPLAY SFMT("  %1 %2: %3 tests, %4 failed, %5 errors, %6 skipped (%7 s)",
        Internal.colorize(optColor, color, sym),
        s.name, s.tests, s.failures, s.errors, s.skipped, NVL(s.timeSec, "0"))
END FUNCTION

PRIVATE FUNCTION printSummary(t Aggregator.Totals, stoppedEarly BOOLEAN)
    DEFINE color STRING
    DEFINE passed INTEGER
    LET passed = t.tests - t.failures - t.errors - t.skipped
    IF t.failures > 0 OR t.errors > 0 THEN
        LET color = Internal.ANSI_RED
    ELSE
        LET color = Internal.ANSI_GREEN
    END IF
    DISPLAY ""
    IF stoppedEarly THEN
        DISPLAY "(stopped early - --fail-fast)"
    END IF
    DISPLAY Internal.colorize(optColor, color,
        SFMT("Suites: %1  Tests: %2  Passed: %3  Failed: %4  Errors: %5  Skipped: %6",
            t.suites, t.tests, passed, t.failures, t.errors, t.skipped))
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
            WHEN arg == "--allow-empty"
                LET optAllowEmpty = TRUE
            WHEN arg == "--junit"
                LET optJunit = needValue(arg, i, n)
                LET i = i + 1
            WHEN arg == "--filter"
                LET optFilter = needValue(arg, i, n)
                LET i = i + 1
            WHEN arg == "--seed"
                LET optSeed = needNumber(arg, i, n)
                LET i = i + 1
            WHEN arg == "--fuzz-runs"
                LET optFuzzRuns = needNumber(arg, i, n)
                LET i = i + 1
            WHEN arg == "--fuzz-size"
                LET optFuzzSize = needNumber(arg, i, n)
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

#+ The value of a numeric option: one to ten digits, or a usage error.
PRIVATE FUNCTION needNumber(flag STRING, i INTEGER, n INTEGER) RETURNS STRING
   VAR text STRING = needValue(flag, i, n)
   VAR re util.Regexp = util.Regexp.compile("^[0-9]{1,10}$")
   IF NOT re.matches(text) THEN
      DISPLAY SFMT("fglunit-run: option '%1' needs a non-negative whole number (got '%2')",
         flag, text)
      EXIT PROGRAM 2
   END IF
   RETURN text
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
    DEFINE h, i INTEGER
    DEFINE name, low STRING
    DEFINE found DYNAMIC ARRAY OF STRING
    LET h = os.Path.dirOpen(dir)
    IF h == 0 THEN
        DISPLAY SFMT("fglunit-run: cannot open directory '%1'", dir)
        EXIT PROGRAM 2
    END IF
    WHILE TRUE
        LET name = os.Path.dirNext(h)
        IF name IS NULL OR name == "" THEN EXIT WHILE END IF
        LET low = name.toLowerCase()
        IF Internal.endsWith(low, ".run.42m") THEN
            LET found[found.getLength() + 1] = name
        END IF
    END WHILE
    CALL os.Path.dirClose(h)

    # dirNext() yields filesystem order, which varies by machine. Sort so
    # the suite order in the aggregated report is reproducible.
    CALL Internal.sortNames(found)
    FOR i = 1 TO found.getLength()
        LET progs[progs.getLength() + 1] = os.Path.join(dir, found[i])
    END FOR
END FUNCTION

# Helpers -----------------------------------------------------------

# A writable temp directory, probed OS-agnostically: TMPDIR (Unix) then
# TEMP / TMP (Windows), falling back to the current directory. os.Path.join
# applies the platform directory separator.
#
# The name carries a random component and the path is rejected if it
# already exists. "fglunit.<pid>.<n>.xml" was guessable, and on a shared
# CI runner /tmp is world-writable: anyone able to predict the name could
# pre-create a symlink and have the driver write through it. BDL exposes
# no O_EXCL, so this narrows the window rather than closing it — which is
# why the name is unguessable in the first place.
PRIVATE FUNCTION tempPath(idx INTEGER, ext STRING) RETURNS STRING
    DEFINE dir, path STRING
    DEFINE attempt INTEGER

    LET dir = fgl_getenv("TMPDIR")
    IF dir IS NULL OR dir.getLength() == 0 THEN LET dir = fgl_getenv("TEMP") END IF
    IF dir IS NULL OR dir.getLength() == 0 THEN LET dir = fgl_getenv("TMP") END IF
    IF dir IS NULL OR dir.getLength() == 0 THEN LET dir = os.Path.pwd() END IF

    FOR attempt = 1 TO 20
        LET path = os.Path.join(dir,
            SFMT("fglunit.%1.%2.%3.%4", fgl_getpid(), idx,
                 util.Math.rand(1000000000), ext))
        IF NOT os.Path.exists(path) THEN
            RETURN path
        END IF
    END FOR

    DISPLAY SFMT("fglunit-run: cannot find an unused temporary file name in '%1'", dir)
    EXIT PROGRAM 2
    RETURN NULL   # unreachable; the compiler cannot see EXIT PROGRAM ends the function
END FUNCTION

PRIVATE FUNCTION tailOf(s STRING) RETURNS STRING
    IF s IS NULL THEN RETURN NULL END IF
    IF s.getLength() <= 800 THEN RETURN s END IF
    RETURN s.subString(s.getLength() - 800 + 1, s.getLength())
END FUNCTION

PRIVATE FUNCTION stem(fileName STRING) RETURNS STRING
    DEFINE low STRING
    LET low = fileName.toLowerCase()
    IF Internal.endsWith(low, ".run.42m") THEN
        RETURN fileName.subString(1, fileName.getLength() - 8)
    END IF
    IF Internal.endsWith(low, ".42m") THEN
        RETURN fileName.subString(1, fileName.getLength() - 4)
    END IF
    RETURN fileName
END FUNCTION

PRIVATE FUNCTION usage()
    DISPLAY "Usage: fglrun fglunit_run.42m [options] <program.42m> ..."
    DISPLAY ""
    DISPLAY "Options:"
    DISPLAY "  --dir <d>       Run every *.run.42m under <d> (non-recursive)"
    DISPLAY "  --junit <file>  Write the aggregated <testsuites> XML"
    DISPLAY "  --filter <pat>  Passed through to each child suite"
    DISPLAY "  --seed <n>      Passed through: base seed for fuzz targets"
    DISPLAY "  --fuzz-runs <n> Passed through: runs per fuzz target"
    DISPLAY "  --fuzz-size <n> Passed through: fuzz input size"
    DISPLAY "  --fail-fast     Stop after the first failing suite"
    DISPLAY "  --allow-empty   Exit 0 even when no suite ran a test"
    DISPLAY "  -v, --verbose   Echo each child's console output"
    DISPLAY "  --color <mode>  auto (default) | always | never"
    DISPLAY "  -h, --help      Show this help"
    DISPLAY ""
    DISPLAY "Exit code: 0 when all suites pass, 1 on failure or when no"
    DISPLAY "test ran (see --allow-empty), 2 on a usage error."
END FUNCTION
