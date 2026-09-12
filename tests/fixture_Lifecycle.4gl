# Fixture program for integration.sh — deliberately NOT green.
#
# It contains a passing, a failing, an erroring and a skipping test so the
# driver can assert on exit codes, filter behaviour and fixture ordering —
# none of which a suite can assert about itself, because it would have to
# re-enter FglUnit.run() from inside a test.

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL com.fourjs.fglunit.Assertions

PRIVATE DEFINE setups, teardowns INTEGER

MAIN
    CALL CliArgs.parse()
    CALL FglUnit.suite("lifecycle")
    CALL FglUnit.setSetup(FUNCTION su)
    CALL FglUnit.setTeardown(FUNCTION td)
    CALL FglUnit.register("alpha_passes",     FUNCTION test_alpha_passes)
    CALL FglUnit.register("beta_fails",       FUNCTION test_beta_fails)
    CALL FglUnit.register("gamma_errors",     FUNCTION test_gamma_errors)
    CALL FglUnit.register("delta_skips",      FUNCTION test_delta_skips)
    CALL FglUnit.register("epsilon_skip_then_fails", FUNCTION test_epsilon_skip_then_fails)
    CALL FglUnit.register("zeta_reports",     FUNCTION test_zeta_reports)
    EXIT PROGRAM FglUnit.run()
END MAIN

PUBLIC FUNCTION su()
    LET setups = setups + 1
END FUNCTION

PUBLIC FUNCTION td()
    LET teardowns = teardowns + 1
END FUNCTION

PUBLIC FUNCTION test_alpha_passes()
    CALL Assertions.assertTrue(TRUE, "ok")
END FUNCTION

PUBLIC FUNCTION test_beta_fails()
    CALL Assertions.fail("deliberate failure")
END FUNCTION

PUBLIC FUNCTION test_gamma_errors()
    DEFINE x, z INTEGER
    WHENEVER ANY ERROR RAISE
    LET z = 0
    LET x = 10 / z
END FUNCTION

PUBLIC FUNCTION test_delta_skips()
    CALL Assertions.skip("nothing to see")
    RETURN
END FUNCTION

# skip() cannot abort, so the assertion below still runs. A real failure
# must outrank the skip rather than hide behind it.
PUBLIC FUNCTION test_epsilon_skip_then_fails()
    CALL Assertions.skip("skipped first")
    CALL Assertions.fail("but this failure is real")
END FUNCTION

# Runs last: reports how often the fixtures fired across the five tests
# before it, plus its own setUp. tearDown must have run for the erroring
# test too.
PUBLIC FUNCTION test_zeta_reports()
    DISPLAY SFMT("FIXTURES setUp=%1 tearDown=%2", setups, teardowns)
END FUNCTION
