# Second example suite — exists so the aggregating driver (fglunit-run)
# has more than one suite to merge into a single report.

IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL Calculator

PUBLIC FUNCTION test_add_is_commutative()
    CALL Assertions.assertEqualsInt(Calculator.add(7, 5), Calculator.add(5, 7),
        "a + b == b + a")
END FUNCTION

PUBLIC FUNCTION test_mul_by_zero()
    CALL Assertions.assertEqualsInt(0, Calculator.mul(123, 0), "n * 0 == 0")
END FUNCTION

PUBLIC FUNCTION test_max_equal_values()
    CALL Assertions.assertEqualsInt(5, Calculator.max(5, 5), "max(5, 5)")
END FUNCTION

PUBLIC FUNCTION test_big_multiplication_skipped()
    CALL Assertions.skip("overflow behavior not specified yet")
END FUNCTION
