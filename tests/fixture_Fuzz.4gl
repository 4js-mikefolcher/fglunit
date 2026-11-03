# Fixture program for integration.sh -- deliberately NOT green.
#
# It holds fuzz targets and parametrized tests that pass, fail and error,
# so the driver can check what a suite cannot check about itself: exit
# codes, the seed line, the failure message with its replay options, that
# a replay reproduces the failure, and that bad options exit 2.

IMPORT util

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.Fuzz

PRIVATE TYPE tAdd RECORD
   a        INTEGER,
   b        INTEGER,
   expected INTEGER
END RECORD

MAIN
   VAR goodRows DYNAMIC ARRAY OF tAdd
   VAR badRows DYNAMIC ARRAY OF tAdd
   VAR noRows DYNAMIC ARRAY OF tAdd
   CALL CliArgs.parse()
   CALL FglUnit.suite("fuzz fixture")

   CALL FglUnit.registerFuzz("okFuzz", FUNCTION fuzzOk, 50)
   CALL FglUnit.registerFuzz("badFuzz", FUNCTION fuzzBad, 200)
   CALL FglUnit.registerFuzz("errFuzz", FUNCTION fuzzErr, 200)

   LET goodRows[1].a = 1
   LET goodRows[1].b = 2
   LET goodRows[1].expected = 3
   LET goodRows[2].a = -4
   LET goodRows[2].b = 4
   LET goodRows[2].expected = 0
   LET badRows[1].a = 1
   LET badRows[1].b = 1
   LET badRows[1].expected = 2
   LET badRows[2].a = 2
   LET badRows[2].b = 2
   LET badRows[2].expected = 5
   LET badRows[3].a = 3
   LET badRows[3].b = 3
   LET badRows[3].expected = 6
   CALL FglUnit.registerCases("okCases", FUNCTION checkAdd, util.JSONArray.fromFGL(goodRows))
   CALL FglUnit.registerCases("badCases", FUNCTION checkAdd, util.JSONArray.fromFGL(badRows))
   CALL FglUnit.registerCases("noCases", FUNCTION checkAdd, util.JSONArray.fromFGL(noRows))

   EXIT PROGRAM FglUnit.run()
END MAIN

PRIVATE FUNCTION checkAdd(args util.JSONObject) RETURNS ()
   VAR row tAdd
   CALL args.toFGL(row)
   CALL Assertions.assertEqualsInt(row.expected, row.a + row.b,
      SFMT("%1 + %2", row.a, row.b))
END FUNCTION

# Always holds.
PRIVATE FUNCTION fuzzOk() RETURNS ()
   VAR n INTEGER
   LET n = Fuzz.nextInt(1, 6)
   CALL Assertions.assertTrue(n IS NULL OR (n >= 1 AND n <= 6), "a die roll is 1 to 6")
END FUNCTION

# Fails whenever a string of more than 10 characters is drawn, which a
# 50-character limit makes certain over 200 runs.
PRIVATE FUNCTION fuzzBad() RETURNS ()
   VAR text STRING
   CALL Fuzz.setNullRate(0)
   LET text = Fuzz.nextString(50)
   IF text IS NULL THEN
      RETURN
   END IF
   CALL Assertions.assertTrue(text.getLength() <= 10,
      SFMT("length %1 exceeds 10", text.getLength()))
END FUNCTION

# Raises a runtime error (division by zero) whenever 0 is drawn.
PRIVATE FUNCTION fuzzErr() RETURNS ()
   VAR n INTEGER
   VAR quotient INTEGER
   WHENEVER ANY ERROR RAISE
   CALL Fuzz.setNullRate(0)
   LET n = Fuzz.nextInt(0, 3)
   LET quotient = 12 / n
END FUNCTION
