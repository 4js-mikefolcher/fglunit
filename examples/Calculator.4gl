# Trivial module under test — used by test_Calculator.4gl to
# demonstrate fglunit usage.

PUBLIC FUNCTION add(a INTEGER, b INTEGER) RETURNS INTEGER
    RETURN a + b
END FUNCTION

PUBLIC FUNCTION sub(a INTEGER, b INTEGER) RETURNS INTEGER
    RETURN a - b
END FUNCTION

PUBLIC FUNCTION mul(a INTEGER, b INTEGER) RETURNS INTEGER
    RETURN a * b
END FUNCTION

# Returns a / b. Raises -1202 (division by zero) if b == 0.
# WHENEVER ANY ERROR RAISE so callers can wrap in TRY/CATCH or
# assertThrows.
PUBLIC FUNCTION divide(a INTEGER, b INTEGER) RETURNS INTEGER
    WHENEVER ANY ERROR RAISE
    RETURN a / b
END FUNCTION

# Returns the larger of a and b.
PUBLIC FUNCTION max(a INTEGER, b INTEGER) RETURNS INTEGER
    IF a > b THEN RETURN a END IF
    RETURN b
END FUNCTION
