# Parametrized and fuzz tests for Calculator.
#
# Unlike test_Calculator.4gl this is a hand-written runner (it has a MAIN),
# because registerCases and registerFuzz are called from code, not found by
# fglunit-gen.
#
#   fglrun CalculatorFuzz.42m                  random seed, printed
#   fglrun CalculatorFuzz.42m --seed 1         repeatable
#   fglrun CalculatorFuzz.42m --fuzz-runs 1000 more runs

IMPORT util

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL com.fourjs.fglunit.Fuzz
IMPORT FGL Calculator

PRIVATE TYPE tDivision RECORD
   dividend INTEGER,
   divisor  INTEGER,
   expected INTEGER
END RECORD

MAIN
   VAR divisions DYNAMIC ARRAY OF tDivision
   CALL CliArgs.parse()
   CALL FglUnit.suite("Calculator cases and properties")

   # One test per row: divide[1], divide[2], ...
   LET divisions[1].dividend = 10
   LET divisions[1].divisor = 2
   LET divisions[1].expected = 5
   LET divisions[2].dividend = -9
   LET divisions[2].divisor = 3
   LET divisions[2].expected = -3
   LET divisions[3].dividend = 0
   LET divisions[3].divisor = 7
   LET divisions[3].expected = 0
   CALL FglUnit.registerCases("divide", FUNCTION checkDivide,
      util.JSONArray.fromFGL(divisions))

   # Properties: each run draws fresh inputs, 100 runs by default.
   CALL FglUnit.registerFuzz("addIsCommutative", FUNCTION propAddCommutes, NULL)
   CALL FglUnit.registerFuzz("maxIsNotBelowEitherArgument", FUNCTION propMaxBounds, 200)
   CALL FglUnit.registerFuzz("subUndoesAdd", FUNCTION propSubUndoesAdd, NULL)

   EXIT PROGRAM FglUnit.run()
END MAIN

PRIVATE FUNCTION checkDivide(args util.JSONObject) RETURNS ()
   VAR row tDivision
   CALL args.toFGL(row)
   CALL Assertions.assertEqualsInt(row.expected, Calculator.divide(row.dividend, row.divisor),
      SFMT("%1 / %2", row.dividend, row.divisor))
END FUNCTION

PRIVATE FUNCTION propAddCommutes() RETURNS ()
   VAR a INTEGER
   VAR b INTEGER
   # Bounded so that a + b cannot overflow INTEGER, which is not what
   # this property is about.
   CALL Fuzz.setNullRate(0)
   LET a = Fuzz.nextInt(-1000000000, 1000000000)
   LET b = Fuzz.nextInt(-1000000000, 1000000000)
   CALL Assertions.assertEqualsInt(Calculator.add(a, b), Calculator.add(b, a),
      "a + b == b + a")
END FUNCTION

PRIVATE FUNCTION propMaxBounds() RETURNS ()
   VAR a INTEGER
   VAR b INTEGER
   VAR m INTEGER
   CALL Fuzz.setNullRate(0)
   LET a = Fuzz.nextInt(NULL, NULL)
   LET b = Fuzz.nextInt(NULL, NULL)
   LET m = Calculator.max(a, b)
   CALL Assertions.assertTrue(m >= a AND m >= b, SFMT("max(%1, %2) = %3", a, b, m))
   CALL Assertions.assertTrue(m = a OR m = b, "max is one of its arguments")
END FUNCTION

PRIVATE FUNCTION propSubUndoesAdd() RETURNS ()
   VAR a INTEGER
   VAR b INTEGER
   CALL Fuzz.setNullRate(0)
   LET a = Fuzz.nextInt(-1000000000, 1000000000)
   LET b = Fuzz.nextInt(-1000000000, 1000000000)
   CALL Assertions.assertEqualsInt(a, Calculator.sub(Calculator.add(a, b), b),
      "(a + b) - b == a")
END FUNCTION
