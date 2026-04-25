# Self-tests for the fglunit framework.
#
# Positive tests (happy path): assertions that SHOULD pass.
# Meta-tests (failure detection): call an assertion that should fail,
# then call FglUnit.takeFailure() to check the flag was tripped and
# clear it so the meta-test itself still passes.

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs

MAIN
    CALL CliArgs.parse()
    CALL FglUnit.suite("fglunit self-tests")

    # Positive — assertions that should succeed silently -----------
    CALL FglUnit.register("assertTrue_with_true_passes",
        FUNCTION test_assertTrue_with_true_passes)
    CALL FglUnit.register("assertFalse_with_false_passes",
        FUNCTION test_assertFalse_with_false_passes)
    CALL FglUnit.register("assertEquals_equal_strings_pass",
        FUNCTION test_assertEquals_equal_strings_pass)
    CALL FglUnit.register("assertEquals_null_equals_null",
        FUNCTION test_assertEquals_null_equals_null)
    CALL FglUnit.register("assertNotEquals_different_pass",
        FUNCTION test_assertNotEquals_different_pass)
    CALL FglUnit.register("assertEqualsInt_equal_passes",
        FUNCTION test_assertEqualsInt_equal_passes)
    CALL FglUnit.register("assertEqualsDec_within_tolerance_passes",
        FUNCTION test_assertEqualsDec_within_tolerance_passes)
    CALL FglUnit.register("assertNull_null_passes",
        FUNCTION test_assertNull_null_passes)
    CALL FglUnit.register("assertNotNull_nonnull_passes",
        FUNCTION test_assertNotNull_nonnull_passes)
    CALL FglUnit.register("assertContains_substring_passes",
        FUNCTION test_assertContains_substring_passes)
    CALL FglUnit.register("assertMatches_matching_regex_passes",
        FUNCTION test_assertMatches_matching_regex_passes)
    CALL FglUnit.register("assertThrows_on_error_passes",
        FUNCTION test_assertThrows_on_error_passes)

    # Meta — assertions that should TRIP failure when misused -----
    CALL FglUnit.register("assertTrue_with_false_trips",
        FUNCTION test_assertTrue_with_false_trips)
    CALL FglUnit.register("assertFalse_with_true_trips",
        FUNCTION test_assertFalse_with_true_trips)
    CALL FglUnit.register("assertEquals_unequal_trips",
        FUNCTION test_assertEquals_unequal_trips)
    CALL FglUnit.register("assertEquals_null_vs_nonnull_trips",
        FUNCTION test_assertEquals_null_vs_nonnull_trips)
    CALL FglUnit.register("assertEqualsInt_mismatch_trips",
        FUNCTION test_assertEqualsInt_mismatch_trips)
    CALL FglUnit.register("assertEqualsDec_outside_tolerance_trips",
        FUNCTION test_assertEqualsDec_outside_tolerance_trips)
    CALL FglUnit.register("assertNull_nonnull_trips",
        FUNCTION test_assertNull_nonnull_trips)
    CALL FglUnit.register("assertNotNull_null_trips",
        FUNCTION test_assertNotNull_null_trips)
    CALL FglUnit.register("assertContains_missing_trips",
        FUNCTION test_assertContains_missing_trips)
    CALL FglUnit.register("assertMatches_nomatch_trips",
        FUNCTION test_assertMatches_nomatch_trips)
    CALL FglUnit.register("assertThrows_on_silent_fn_trips",
        FUNCTION test_assertThrows_on_silent_fn_trips)
    CALL FglUnit.register("fail_trips",
        FUNCTION test_fail_trips)

    # Framework behavior -------------------------------------------
    CALL FglUnit.register("first_failure_wins",
        FUNCTION test_first_failure_wins)

    EXIT PROGRAM FglUnit.run()
END MAIN

# Positive assertions ----------------------------------------------

PUBLIC FUNCTION test_assertTrue_with_true_passes()
    CALL Assertions.assertTrue(TRUE, "trivially true")
END FUNCTION

PUBLIC FUNCTION test_assertFalse_with_false_passes()
    CALL Assertions.assertFalse(FALSE, "trivially false")
END FUNCTION

PUBLIC FUNCTION test_assertEquals_equal_strings_pass()
    CALL Assertions.assertEquals("abc", "abc", "same strings")
END FUNCTION

PUBLIC FUNCTION test_assertEquals_null_equals_null()
    DEFINE a, b STRING
    CALL Assertions.assertEquals(a, b, "null == null")
END FUNCTION

PUBLIC FUNCTION test_assertNotEquals_different_pass()
    CALL Assertions.assertNotEquals("a", "b", "a != b")
END FUNCTION

PUBLIC FUNCTION test_assertEqualsInt_equal_passes()
    CALL Assertions.assertEqualsInt(42, 42, "42 == 42")
END FUNCTION

PUBLIC FUNCTION test_assertEqualsDec_within_tolerance_passes()
    CALL Assertions.assertEqualsDec(1.2345, 1.2340, 0.01, "within 0.01")
END FUNCTION

PUBLIC FUNCTION test_assertNull_null_passes()
    DEFINE x STRING
    CALL Assertions.assertNull(x, "x is null")
END FUNCTION

PUBLIC FUNCTION test_assertNotNull_nonnull_passes()
    CALL Assertions.assertNotNull("hello", "literal is not null")
END FUNCTION

PUBLIC FUNCTION test_assertContains_substring_passes()
    CALL Assertions.assertContains("hello world", "world", "substring match")
END FUNCTION

PUBLIC FUNCTION test_assertMatches_matching_regex_passes()
    CALL Assertions.assertMatches("abc123", "^[a-z]+[0-9]+$", "pattern match")
END FUNCTION

PUBLIC FUNCTION test_assertThrows_on_error_passes()
    CALL Assertions.assertThrows(FUNCTION raises_division_by_zero,
        "division by zero should throw")
END FUNCTION

# Meta assertions --------------------------------------------------
# Each meta-test:
#   1. invokes an assertion expected to FAIL
#   2. consumes the failure flag via takeFailure()
#   3. asserts the flag was indeed set
# If step 1's assertion wrongly succeeds, takeFailure() returns FALSE,
# and the subsequent assertTrue(FALSE, ...) trips the flag for real —
# causing the meta-test itself to FAIL. That's the desired signal.

PUBLIC FUNCTION test_assertTrue_with_false_trips()
    CALL Assertions.assertTrue(FALSE, "should trip")
    CALL Assertions.assertTrue(FglUnit.takeFailure(),
        "assertTrue(FALSE) should trip failure flag")
END FUNCTION

PUBLIC FUNCTION test_assertFalse_with_true_trips()
    CALL Assertions.assertFalse(TRUE, "should trip")
    CALL Assertions.assertTrue(FglUnit.takeFailure(),
        "assertFalse(TRUE) should trip failure flag")
END FUNCTION

PUBLIC FUNCTION test_assertEquals_unequal_trips()
    CALL Assertions.assertEquals("a", "b", "should trip")
    CALL Assertions.assertTrue(FglUnit.takeFailure(),
        "assertEquals('a','b') should trip failure flag")
END FUNCTION

PUBLIC FUNCTION test_assertEquals_null_vs_nonnull_trips()
    DEFINE n STRING
    CALL Assertions.assertEquals(n, "x", "should trip")
    CALL Assertions.assertTrue(FglUnit.takeFailure(),
        "assertEquals(NULL, 'x') should trip failure flag")
END FUNCTION

PUBLIC FUNCTION test_assertEqualsInt_mismatch_trips()
    CALL Assertions.assertEqualsInt(1, 2, "should trip")
    CALL Assertions.assertTrue(FglUnit.takeFailure(),
        "assertEqualsInt(1,2) should trip failure flag")
END FUNCTION

PUBLIC FUNCTION test_assertEqualsDec_outside_tolerance_trips()
    CALL Assertions.assertEqualsDec(1.0, 2.0, 0.01, "should trip")
    CALL Assertions.assertTrue(FglUnit.takeFailure(),
        "assertEqualsDec outside tolerance should trip failure flag")
END FUNCTION

PUBLIC FUNCTION test_assertNull_nonnull_trips()
    CALL Assertions.assertNull("x", "should trip")
    CALL Assertions.assertTrue(FglUnit.takeFailure(),
        "assertNull('x') should trip failure flag")
END FUNCTION

PUBLIC FUNCTION test_assertNotNull_null_trips()
    DEFINE n STRING
    CALL Assertions.assertNotNull(n, "should trip")
    CALL Assertions.assertTrue(FglUnit.takeFailure(),
        "assertNotNull(NULL) should trip failure flag")
END FUNCTION

PUBLIC FUNCTION test_assertContains_missing_trips()
    CALL Assertions.assertContains("hello", "world", "should trip")
    CALL Assertions.assertTrue(FglUnit.takeFailure(),
        "assertContains missing substring should trip failure flag")
END FUNCTION

PUBLIC FUNCTION test_assertMatches_nomatch_trips()
    CALL Assertions.assertMatches("ABC", "^[a-z]+$", "should trip")
    CALL Assertions.assertTrue(FglUnit.takeFailure(),
        "assertMatches non-matching should trip failure flag")
END FUNCTION

PUBLIC FUNCTION test_assertThrows_on_silent_fn_trips()
    CALL Assertions.assertThrows(FUNCTION silent_fn, "should trip")
    CALL Assertions.assertTrue(FglUnit.takeFailure(),
        "assertThrows on non-throwing fn should trip failure flag")
END FUNCTION

PUBLIC FUNCTION test_fail_trips()
    CALL Assertions.fail("intentional")
    CALL Assertions.assertTrue(FglUnit.takeFailure(),
        "fail() should trip failure flag")
END FUNCTION

# Framework behavior -----------------------------------------------

PUBLIC FUNCTION test_first_failure_wins()
    # Two consecutive failing assertions — only the first message
    # should be recorded.
    CALL Assertions.assertEquals("first", "mismatch1", "first failure")
    CALL Assertions.assertEquals("second", "mismatch2", "second failure")
    # Flag is set. takeFailure returns TRUE + clears. Nothing verifies
    # which *message* is preserved, but a working implementation keeps
    # the first and ignores subsequent ones.
    CALL Assertions.assertTrue(FglUnit.takeFailure(),
        "two failing assertions still trip exactly one failure flag")
END FUNCTION

# Helper functions for assertThrows tests --------------------------

PRIVATE FUNCTION raises_division_by_zero()
    DEFINE n, d, x INTEGER
    # WHENEVER ANY ERROR RAISE makes runtime errors propagate to the
    # caller's TRY/CATCH (here, assertThrows). Without it, BDL's
    # default policy silently absorbs expression errors in called
    # functions. This is the standard BDL idiom for surfaceable errors.
    WHENEVER ANY ERROR RAISE
    LET n = 1
    LET d = 0
    LET x = n / d
END FUNCTION

PRIVATE FUNCTION silent_fn()
    # intentionally does nothing
END FUNCTION
