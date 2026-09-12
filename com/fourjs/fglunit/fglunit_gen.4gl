PACKAGE com.fourjs.fglunit

# fglunit-gen — generate xUnit runner modules from test source.
#
# A test module is a plain .4gl (no PACKAGE, no MAIN) with PUBLIC FUNCTION
# test*() cases and optional PUBLIC fixtures (setUp/tearDown/setUpSuite/
# tearDownSuite). For each input this writes a "<base>.run.4gl" runner that
# registers everything and calls FglUnit.run().
#
# From an installed package:  fglpkg bdl fglunit fglunit_gen [options] <src>...
# In-repo / from a build:     fglrun fglunit_gen.42m [options] <src>...
#     --dir <d>      discover test_*.4gl under <d> (non-recursive)
#     --out <file>   output path (single input only; default <base>.run.4gl)
#     --suite <name> override suite name (single input only)
#     --stdout       write to stdout instead of a file
#     -h, --help

IMPORT os
IMPORT FGL com.fourjs.fglunit.Discovery
IMPORT FGL com.fourjs.fglunit.Internal

PRIVATE DEFINE inputs DYNAMIC ARRAY OF STRING
PRIVATE DEFINE optOut, optSuite STRING
PRIVATE DEFINE optStdout BOOLEAN

MAIN
    DEFINE i INTEGER
    DEFINE hadError BOOLEAN

    CALL parseArgs()

    IF inputs.getLength() == 0 THEN
        DISPLAY "fglunit-gen: no input files (use --dir or pass test_*.4gl)"
        CALL usage()
        EXIT PROGRAM 2
    END IF

    IF inputs.getLength() > 1 AND (optOut IS NOT NULL OR optSuite IS NOT NULL) THEN
        DISPLAY "fglunit-gen: --out/--suite only valid with a single input file"
        EXIT PROGRAM 2
    END IF

    FOR i = 1 TO inputs.getLength()
        IF NOT processFile(inputs[i]) THEN
            LET hadError = TRUE
        END IF
    END FOR

    IF hadError THEN EXIT PROGRAM 1 END IF
    EXIT PROGRAM 0
END MAIN

# Generate one runner. Returns FALSE on a hard error.
PRIVATE FUNCTION processFile(path STRING) RETURNS BOOLEAN
    DEFINE src, moduleName, suite, runnerText, outPath STRING
    DEFINE res Discovery.DiscoveryResult
    DEFINE i INTEGER

    LET src = Internal.readFile(path)
    IF src IS NULL THEN
        DISPLAY SFMT("fglunit-gen: cannot read '%1'", path)
        RETURN FALSE
    END IF

    LET moduleName = stem(os.Path.baseName(path))
    LET res = Discovery.parseSource(src)

    FOR i = 1 TO res.warnings.getLength()
        DISPLAY SFMT("fglunit-gen: %1: warning: %2", path, res.warnings[i])
    END FOR

    IF res.errorMsg IS NOT NULL THEN
        DISPLAY SFMT("fglunit-gen: %1: %2", path, res.errorMsg)
        RETURN FALSE
    END IF

    IF res.tests.getLength() == 0 THEN
        DISPLAY SFMT("fglunit-gen: %1: no test* functions found, skipping", path)
        RETURN TRUE   # not fatal — directory sweeps hit helper modules
    END IF

    IF optSuite IS NOT NULL THEN
        LET suite = optSuite
    ELSE
        LET suite = Discovery.suiteNameFor(moduleName)
    END IF

    LET runnerText = Discovery.renderRunner(moduleName, suite, res)

    IF optStdout THEN
        CALL writeStdout(runnerText)
        RETURN TRUE
    END IF

    IF optOut IS NOT NULL THEN
        LET outPath = optOut
    ELSE
        LET outPath = defaultOut(path, moduleName)
    END IF

    IF NOT Internal.writeFile(outPath, runnerText) THEN
        DISPLAY SFMT("fglunit-gen: cannot write '%1'", outPath)
        RETURN FALSE
    END IF

    DISPLAY SFMT("fglunit-gen: %1 -> %2 (%3 tests)",
        path, outPath, res.tests.getLength())
    RETURN TRUE
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
            WHEN arg == "--stdout"
                LET optStdout = TRUE
            WHEN arg == "--out"
                LET optOut = needValue(arg, i, n)
                LET i = i + 1
            WHEN arg == "--suite"
                LET optSuite = needValue(arg, i, n)
                LET i = i + 1
            WHEN arg == "--dir"
                CALL scanDir(needValue(arg, i, n))
                LET i = i + 1
            WHEN arg.getIndexOf("-", 1) == 1
                DISPLAY SFMT("fglunit-gen: unknown option '%1'", arg)
                CALL usage()
                EXIT PROGRAM 2
            OTHERWISE
                LET inputs[inputs.getLength() + 1] = arg
        END CASE
        LET i = i + 1
    END WHILE
END FUNCTION

PRIVATE FUNCTION needValue(flag STRING, i INTEGER, n INTEGER) RETURNS STRING
    IF i + 1 > n THEN
        DISPLAY SFMT("fglunit-gen: option '%1' requires a value", flag)
        EXIT PROGRAM 2
    END IF
    RETURN arg_val(i + 1)
END FUNCTION

# Append every test_*.4gl in `dir` (non-recursive) to the input list.
PRIVATE FUNCTION scanDir(dir STRING)
    DEFINE h, i INTEGER
    DEFINE name, low STRING
    DEFINE found DYNAMIC ARRAY OF STRING

    LET h = os.Path.dirOpen(dir)
    IF h == 0 THEN
        DISPLAY SFMT("fglunit-gen: cannot open directory '%1'", dir)
        EXIT PROGRAM 2
    END IF
    WHILE TRUE
        LET name = os.Path.dirNext(h)
        IF name IS NULL OR name == "" THEN EXIT WHILE END IF
        LET low = name.toLowerCase()
        IF low.getIndexOf("test", 1) == 1
           AND low.getIndexOf(".run.4gl", 1) == 0
           AND Internal.endsWith(low, ".4gl") THEN
            LET found[found.getLength() + 1] = name
        END IF
    END WHILE
    CALL os.Path.dirClose(h)

    # dirNext() yields entries in filesystem order, which differs between
    # machines. Sort so a directory sweep produces the same suite order —
    # and so the same aggregated report — everywhere.
    CALL Internal.sortNames(found)
    FOR i = 1 TO found.getLength()
        LET inputs[inputs.getLength() + 1] = os.Path.join(dir, found[i])
    END FOR
END FUNCTION

PRIVATE FUNCTION writeStdout(text STRING)
    IF text.getCharAt(text.getLength()) == "\n" THEN
        LET text = text.subString(1, text.getLength() - 1)
    END IF
    DISPLAY text
END FUNCTION

# Path helpers ------------------------------------------------------

# Default output: "<dir>/<base>.run.4gl" next to the source.
PRIVATE FUNCTION defaultOut(srcPath STRING, moduleName STRING) RETURNS STRING
    DEFINE dir STRING
    LET dir = os.Path.dirName(srcPath)
    IF dir IS NULL OR dir == "" OR dir == "." THEN
        RETURN moduleName || ".run.4gl"
    END IF
    RETURN os.Path.join(dir, moduleName || ".run.4gl")
END FUNCTION

# Strip a trailing ".4gl" (case-insensitive) from a file name.
PRIVATE FUNCTION stem(fileName STRING) RETURNS STRING
    IF Internal.endsWith(fileName.toLowerCase(), ".4gl") THEN
        RETURN fileName.subString(1, fileName.getLength() - 4)
    END IF
    RETURN fileName
END FUNCTION

PRIVATE FUNCTION usage()
    DISPLAY "Usage: fglrun fglunit_gen.42m [options] <test-source.4gl> ..."
    DISPLAY ""
    DISPLAY "Options:"
    DISPLAY "  --dir <d>       Discover test_*.4gl under <d> (non-recursive)"
    DISPLAY "  --out <file>    Output path (single input only)"
    DISPLAY "  --suite <name>  Override suite name (single input only)"
    DISPLAY "  --stdout        Write generated runner to stdout"
    DISPLAY "  -h, --help      Show this help"
END FUNCTION
