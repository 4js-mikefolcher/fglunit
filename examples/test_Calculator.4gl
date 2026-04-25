# Example: testing the Calculator module with fglunit.
#
# Demonstrates:
#   * suite + per-test setUp / tearDown
#   * basic assertions (Int, equality, contains)
#   * assertThrows on a function that uses WHENEVER ANY ERROR RAISE
#   * fail() / skip()

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL Calculator

PRIVATE DEFINE setupRan, teardownRan INTEGER

MAIN
    CALL CliArgs.parse()
    CALL FglUnit.suite("Calculator")
    CALL FglUnit.setSetup(FUNCTION before_each)
    CALL FglUnit.setTeardown(FUNCTION after_each)

    CALL FglUnit.register("add_two_positives",
        FUNCTION test_add_two_positives)
    CALL FglUnit.register("add_negative",
        FUNCTION test_add_negative)
    CALL FglUnit.register("sub_basic",
        FUNCTION test_sub_basic)
    CALL FglUnit.register("mul_basic",
        FUNCTION test_mul_basic)
    CALL FglUnit.register("divide_basic",
        FUNCTION test_divide_basic)
    CALL FglUnit.register("divide_by_zero_raises",
        FUNCTION test_divide_by_zero_raises)
    CALL FglUnit.register("max_picks_larger",
        FUNCTION test_max_picks_larger)
    CALL FglUnit.register("setup_was_invoked",
        FUNCTION test_setup_was_invoked)

    EXIT PROGRAM FglUnit.run()
END MAIN

# Fixtures ---------------------------------------------------------

PRIVATE FUNCTION before_each()
    LET setupRan = setupRan + 1
END FUNCTION

PRIVATE FUNCTION after_each()
    LET teardownRan = teardownRan + 1
END FUNCTION

# Tests ------------------------------------------------------------

PUBLIC FUNCTION test_add_two_positives()
    CALL Assertions.assertEqualsInt(5, Calculator.add(2, 3), "2 + 3")
END FUNCTION

PUBLIC FUNCTION test_add_negative()
    CALL Assertions.assertEqualsInt(-1, Calculator.add(2, -3), "2 + -3")
END FUNCTION

PUBLIC FUNCTION test_sub_basic()
    CALL Assertions.assertEqualsInt(7, Calculator.sub(10, 3), "10 - 3")
END FUNCTION

PUBLIC FUNCTION test_mul_basic()
    CALL Assertions.assertEqualsInt(12, Calculator.mul(3, 4), "3 * 4")
END FUNCTION

PUBLIC FUNCTION test_divide_basic()
    CALL Assertions.assertEqualsInt(5, Calculator.divide(10, 2), "10 / 2")
END FUNCTION

PUBLIC FUNCTION test_divide_by_zero_raises()
    CALL Assertions.assertThrows(FUNCTION divide_by_zero_call,
        "divide(10, 0) should raise")
END FUNCTION

PUBLIC FUNCTION test_max_picks_larger()
    CALL Assertions.assertEqualsInt(9, Calculator.max(3, 9), "max(3, 9)")
    CALL Assertions.assertEqualsInt(9, Calculator.max(9, 3), "max(9, 3)")
END FUNCTION

PUBLIC FUNCTION test_setup_was_invoked()
    # By the time this test runs, before_each has been called for
    # every test scheduled so far (including this one). Exact count
    # is fragile, so we just check it ran at least once.
    CALL Assertions.assertTrue(setupRan > 0, "setUp should have run")
END FUNCTION

# Throwaway closure used by assertThrows. WHENEVER ANY ERROR RAISE
# is required here too — `RAISE` only propagates one frame in BDL,
# so every function on the call path between the failing operation
# and the assertThrows TRY/CATCH must opt into propagation.
PRIVATE FUNCTION divide_by_zero_call()
    DEFINE x INTEGER
    WHENEVER ANY ERROR RAISE
    LET x = Calculator.divide(10, 0)
END FUNCTION
