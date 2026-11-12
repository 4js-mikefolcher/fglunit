PACKAGE com.fourjs.fglunit

IMPORT util

IMPORT FGL com.fourjs.fglunit.FglUnit

# Parses command-line flags and pushes them into FglUnit via setters.
# Usage from a test program's MAIN:
#
#     IMPORT FGL com.fourjs.fglunit.FglUnit
#     IMPORT FGL com.fourjs.fglunit.CliArgs
#
#     MAIN
#         CALL CliArgs.parse()
#         ... register tests ...
#         EXIT PROGRAM FglUnit.run()
#     END MAIN
#
# Supported flags:
#   --junit <file>      write JUnit XML output
#   --filter <pattern>  only run tests whose name contains pattern
#   --list              print registered tests and exit 0 (handled by run)
#   -v, --verbose       per-test output
#   --fail-fast         stop on first failure
#   --allow-empty       exit 0 even when no test ran
#   --seed <n>          base seed for fuzz targets
#   --fuzz-runs <n>     runs per fuzz target (0 skips them)
#   --fuzz-size <n>     input size 0-100, to replay a shrunk failure
#   --color <mode>      auto | always | never
#   -h, --help          print usage and exit 0

# Largest values the fuzz options accept: --seed is a BIGINT (10 digits),
# the other two are INTEGERs.
PRIVATE CONSTANT cMaxSeed = 9999999999
PRIVATE CONSTANT cMaxInteger = 2147483647

PUBLIC FUNCTION parse()
    DEFINE n, i INTEGER
    DEFINE arg, next STRING

    LET n = num_args()
    LET i = 1
    WHILE i <= n
        LET arg = arg_val(i)
        CASE
            WHEN arg = "-h" OR arg = "--help"
                CALL printUsage()
                EXIT PROGRAM 0
            WHEN arg = "-v" OR arg = "--verbose"
                CALL FglUnit.setVerbose(TRUE)
            WHEN arg = "--list"
                CALL FglUnit.setListOnly(TRUE)
            WHEN arg = "--fail-fast"
                CALL FglUnit.setFailFast(TRUE)
            WHEN arg = "--allow-empty"
                CALL FglUnit.setAllowEmpty(TRUE)
            WHEN arg = "--junit"
                LET next = consumeValue(arg, i, n)
                LET i = i + 1
                CALL FglUnit.setJunitOutput(next)
            WHEN arg = "--filter"
                LET next = consumeValue(arg, i, n)
                LET i = i + 1
                CALL FglUnit.setFilter(next)
            WHEN arg = "--seed"
                LET next = consumeValue(arg, i, n)
                LET i = i + 1
                CALL FglUnit.setFuzzSeed(parseNumber(arg, next, cMaxSeed))
            WHEN arg = "--fuzz-runs"
                LET next = consumeValue(arg, i, n)
                LET i = i + 1
                CALL FglUnit.setFuzzRuns(parseNumber(arg, next, cMaxInteger))
            WHEN arg = "--fuzz-size"
                LET next = consumeValue(arg, i, n)
                LET i = i + 1
                CALL FglUnit.setFuzzSize(parseNumber(arg, next, cMaxInteger))
            WHEN arg = "--color"
                LET next = consumeValue(arg, i, n)
                LET i = i + 1
                CASE next
                    WHEN "auto"   CALL FglUnit.setColorMode("auto")
                    WHEN "always" CALL FglUnit.setColorMode("always")
                    WHEN "never"  CALL FglUnit.setColorMode("never")
                    OTHERWISE
                        DISPLAY SFMT("fglunit: --color must be auto|always|never (got '%1')", next)
                        EXIT PROGRAM 2
                END CASE
            OTHERWISE
                DISPLAY SFMT("fglunit: unknown option '%1'", arg)
                CALL printUsage()
                EXIT PROGRAM 2
        END CASE
        LET i = i + 1
    END WHILE
END FUNCTION

PRIVATE FUNCTION consumeValue(flag STRING, i INTEGER, n INTEGER) RETURNS STRING
    IF i + 1 > n THEN
        DISPLAY SFMT("fglunit: option '%1' requires a value", flag)
        EXIT PROGRAM 2
    END IF
    RETURN arg_val(i + 1)
END FUNCTION

#+ A whole number from 0 to largest (at most 10 digits), or a usage error
#+ (exit 2). The range matters: the value goes into an INTEGER or BIGINT
#+ setter, and a number too big for it would become NULL, which the setter
#+ reads as "option not given" and silently ignores.
PRIVATE FUNCTION parseNumber(flag STRING, text STRING, largest BIGINT) RETURNS BIGINT
   VAR re util.Regexp = util.Regexp.compile("^[0-9]{1,10}$")
   VAR value BIGINT = 0
   VAR valid BOOLEAN = FALSE
   IF text IS NOT NULL AND re.matches(text) THEN
      LET value = text
      LET valid = (value <= largest)
   END IF
   IF NOT valid THEN
      DISPLAY SFMT("fglunit: option '%1' needs a whole number from 0 to %2 (got '%3')",
         flag, largest, NVL(text, ""))
      EXIT PROGRAM 2
   END IF
   RETURN value
END FUNCTION

PRIVATE FUNCTION printUsage()
    DISPLAY "Usage: fglrun <test_program>.42m [options]"
    DISPLAY ""
    DISPLAY "Options:"
    DISPLAY "  --junit <file>       Write JUnit XML to <file>"
    DISPLAY "  --filter <pattern>   Run only tests whose name contains <pattern>"
    DISPLAY "  --list               Print registered tests and exit"
    DISPLAY "  -v, --verbose        Per-test output"
    DISPLAY "  --fail-fast          Stop on first failure"
    DISPLAY "  --allow-empty        Exit 0 even when no test ran"
    DISPLAY "  --seed <n>           Base seed for fuzz targets (run k uses n + k - 1)"
    DISPLAY "  --fuzz-runs <n>      Runs per fuzz target (0 skips them)"
    DISPLAY "  --fuzz-size <n>      Input size 0-100 (replays a shrunk failure)"
    DISPLAY "  --color <mode>       auto (default) | always | never"
    DISPLAY "                       auto also honours NO_COLOR and TERM=dumb"
    DISPLAY "  -h, --help           Show this help"
    DISPLAY ""
    DISPLAY "Exit code: 0 when all tests pass, 1 on failure or when no"
    DISPLAY "test ran (see --allow-empty), 2 on a usage error."
END FUNCTION
