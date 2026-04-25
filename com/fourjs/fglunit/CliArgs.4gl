PACKAGE com.fourjs.fglunit

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
#   --color <mode>      auto | always | never
#   -h, --help          print usage and exit 0

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
            WHEN arg = "--junit"
                LET next = consumeValue(arg, i, n)
                LET i = i + 1
                CALL FglUnit.setJunitOutput(next)
            WHEN arg = "--filter"
                LET next = consumeValue(arg, i, n)
                LET i = i + 1
                CALL FglUnit.setFilter(next)
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

PRIVATE FUNCTION printUsage()
    DISPLAY "Usage: fglrun <test_program>.42m [options]"
    DISPLAY ""
    DISPLAY "Options:"
    DISPLAY "  --junit <file>       Write JUnit XML to <file>"
    DISPLAY "  --filter <pattern>   Run only tests whose name contains <pattern>"
    DISPLAY "  --list               Print registered tests and exit"
    DISPLAY "  -v, --verbose        Per-test output"
    DISPLAY "  --fail-fast          Stop on first failure"
    DISPLAY "  --color <mode>       auto (default) | always | never"
    DISPLAY "  -h, --help           Show this help"
    DISPLAY ""
    DISPLAY "Exit code: 0 when all tests pass, 1 otherwise."
END FUNCTION
