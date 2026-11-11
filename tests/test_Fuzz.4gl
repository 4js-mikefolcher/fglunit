# Self-tests for the Fuzz generators, run through FglUnit itself: the
# parametrized (registerCases) and fuzz (registerFuzz) entry points are used
# here on their own generators, so a regression shows up in both places.
#
# What cannot be asserted from inside a suite -- a failing fuzz target, its
# shrinking and its replay command -- is checked by integration.sh against
# fixture_Fuzz.

IMPORT util

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL com.fourjs.fglunit.Fuzz

PRIVATE TYPE tBound RECORD
   lowest  INTEGER,
   highest INTEGER
END RECORD

MAIN
   VAR bounds DYNAMIC ARRAY OF tBound
   CALL CliArgs.parse()
   CALL FglUnit.suite("Fuzz generators")

   CALL FglUnit.register("seedReplaysTheSameValues", FUNCTION testSeedReplays)
   CALL FglUnit.register("differentSeedsDiffer", FUNCTION testSeedsDiffer)
   CALL FglUnit.register("beginFoldsAnySeedIntoRange", FUNCTION testBeginFolds)
   CALL FglUnit.register("intReachesTheWholeRange", FUNCTION testIntWholeRange)
   CALL FglUnit.register("nullRateIsHonoured", FUNCTION testNullRate)
   CALL FglUnit.register("nullIsGeneratedByDefault", FUNCTION testNullByDefault)
   CALL FglUnit.register("stringHonoursMaxLength", FUNCTION testStringLength)
   CALL FglUnit.register("stringsIncludeAwkwardInput", FUNCTION testStringAwkward)
   CALL FglUnit.register("smallSizeKeepsValuesSmall", FUNCTION testSmallSize)
   CALL FglUnit.register("dateStaysInRangeAndHitsEdges", FUNCTION testDate)
   CALL FglUnit.register("decimalStaysInRange", FUNCTION testDecimal)
   CALL FglUnit.register("countIsBoundedAndNeverNull", FUNCTION testCount)
   CALL FglUnit.register("booleanYieldsBothValues", FUNCTION testBoolean)
   CALL FglUnit.register("traceRecordsTheInputs", FUNCTION testTrace)
   CALL FglUnit.register("unseededGeneratorsStillWork", FUNCTION testUnseeded)
   CALL FglUnit.register("beginSurvivesHugeSeeds", FUNCTION testBeginHugeSeed)
   CALL FglUnit.register("stringsIncludeTabAndNewline", FUNCTION testStringTabNewline)
   CALL FglUnit.register("consecutiveSeedsAreIndependent", FUNCTION testSeedsIndependent)
   CALL FglUnit.register("drawsWithinARunAreIndependent", FUNCTION testDrawsIndependent)

   # Parametrized: one run per row, named intInBounds[1] ... intInBounds[5].
   LET bounds[1].lowest = 1
   LET bounds[1].highest = 1
   LET bounds[2].lowest = -5
   LET bounds[2].highest = 5
   LET bounds[3].lowest = 0
   LET bounds[3].highest = 0
   LET bounds[4].lowest = 2147483646
   LET bounds[4].highest = 2147483647
   LET bounds[5].lowest = -2147483647
   LET bounds[5].highest = -2147483646
   CALL FglUnit.registerCases("intInBounds", FUNCTION checkIntInBounds,
      util.JSONArray.fromFGL(bounds))

   # Fuzz target: the generator is fuzzed with its own output.
   CALL FglUnit.registerFuzz("stringNeverExceedsMaxLength", FUNCTION fuzzStringLength, 50)

   EXIT PROGRAM FglUnit.run()
END MAIN

# Helpers ------------------------------------------------------------

#+ Draw count of each generator and return everything drawn as one string,
#+ so two runs can be compared value for value.
PRIVATE FUNCTION drawMixed(count INTEGER) RETURNS STRING
   VAR buffer base.StringBuffer = base.StringBuffer.create()
   VAR i INTEGER
   FOR i = 1 TO count
      CALL buffer.append(SFMT("%1|%2|%3|%4|%5;",
         Fuzz.nextInt(NULL, NULL), Fuzz.nextString(30), Fuzz.nextDate(),
         Fuzz.nextDecimal(NULL, NULL), Fuzz.nextBoolean()))
   END FOR
   RETURN buffer.toString()
END FUNCTION

#+ Pearson's chi-square statistic of independence for pairs of dice rolls
#+ (values 1 to 6), 25 degrees of freedom. The expected count of each cell
#+ comes from the row and column totals, so a generator that favours some
#+ values (nextInt does, toward its bounds) is not mistaken for a dependent
#+ one. Independent rolls give about 25 and rarely more than 60.
PRIVATE FUNCTION independence(first DYNAMIC ARRAY OF INTEGER,
      second DYNAMIC ARRAY OF INTEGER) RETURNS DECIMAL(20,4)
   VAR cells DYNAMIC ARRAY OF INTEGER
   VAR rowTotal DYNAMIC ARRAY OF INTEGER
   VAR colTotal DYNAMIC ARRAY OF INTEGER
   VAR i INTEGER
   VAR r INTEGER
   VAR c INTEGER
   VAR expected DECIMAL(20,6)
   VAR chi DECIMAL(20,4) = 0
   FOR i = 1 TO 36
      LET cells[i] = 0
   END FOR
   FOR i = 1 TO 6
      LET rowTotal[i] = 0
      LET colTotal[i] = 0
   END FOR
   FOR i = 1 TO first.getLength()
      LET cells[(first[i] - 1) * 6 + second[i]] = cells[(first[i] - 1) * 6 + second[i]] + 1
      LET rowTotal[first[i]] = rowTotal[first[i]] + 1
      LET colTotal[second[i]] = colTotal[second[i]] + 1
   END FOR
   FOR r = 1 TO 6
      FOR c = 1 TO 6
         LET expected = rowTotal[r] * colTotal[c] / first.getLength()
         IF expected > 0 THEN
            LET chi = chi + (cells[(r - 1) * 6 + c] - expected)
               * (cells[(r - 1) * 6 + c] - expected) / expected
         END IF
      END FOR
   END FOR
   RETURN chi
END FUNCTION

# Tests --------------------------------------------------------------

PRIVATE FUNCTION testSeedReplays() RETURNS ()
   VAR first STRING
   CALL Fuzz.seed(5)
   LET first = drawMixed(200)
   CALL Fuzz.seed(5)
   CALL Assertions.assertEquals(first, drawMixed(200), "same seed, same values")
END FUNCTION

PRIVATE FUNCTION testSeedsDiffer() RETURNS ()
   VAR first STRING
   CALL Fuzz.seed(5)
   LET first = drawMixed(50)
   CALL Fuzz.seed(6)
   CALL Assertions.assertNotEquals(first, drawMixed(50), "seed 5 and seed 6")
END FUNCTION

PRIVATE FUNCTION testBeginFolds() RETURNS ()
   VAR values DYNAMIC ARRAY OF BIGINT
   VAR i INTEGER
   VAR used INTEGER
   LET values[1] = 0
   LET values[2] = 1
   LET values[3] = 2147483646
   LET values[4] = 2147483647
   LET values[5] = 4294967293
   LET values[6] = -42
   FOR i = 1 TO values.getLength()
      LET used = Fuzz.begin(values[i], Fuzz.cFullSize)
      CALL Assertions.assertTrue(used >= 1 AND used <= 2147483646,
         SFMT("seed %1 folded to %2", values[i], used))
      CALL Assertions.assertEqualsInt(used, Fuzz.begin(used, Fuzz.cFullSize),
         SFMT("folding %1 twice changes it", values[i]))
   END FOR
   CALL Assertions.assertEqualsInt(1, Fuzz.begin(NULL, NULL), "NULL seed is 1")
   CALL Assertions.assertEqualsInt(5, Fuzz.begin(-5, NULL), "sign is dropped")
   CALL Assertions.assertEqualsInt(Fuzz.cFullSize, Fuzz.getSize(), "NULL size is full")
END FUNCTION

PRIVATE FUNCTION testIntWholeRange() RETURNS ()
   VAR i INTEGER
   VAR n INTEGER
   VAR sawHigh BOOLEAN = FALSE
   VAR sawLow BOOLEAN = FALSE
   CALL Fuzz.seed(1)
   CALL Fuzz.setNullRate(0)
   FOR i = 1 TO 2000
      LET n = Fuzz.nextInt(NULL, NULL)
      IF n = 2147483647 THEN
         LET sawHigh = TRUE
      END IF
      IF n = -2147483647 THEN
         LET sawLow = TRUE
      END IF
   END FOR
   CALL Assertions.assertTrue(sawHigh, "the largest INTEGER is generated")
   CALL Assertions.assertTrue(sawLow, "the smallest INTEGER is generated")
END FUNCTION

PRIVATE FUNCTION testNullRate() RETURNS ()
   VAR i INTEGER
   VAR nulls INTEGER = 0
   CALL Fuzz.seed(2)
   CALL Fuzz.setNullRate(0)
   FOR i = 1 TO 500
      IF Fuzz.nextInt(1, 6) IS NULL THEN
         LET nulls = nulls + 1
      END IF
   END FOR
   CALL Assertions.assertEqualsInt(0, nulls, "rate 0 never yields NULL")
   CALL Fuzz.setNullRate(100)
   FOR i = 1 TO 500
      IF Fuzz.nextInt(1, 6) IS NULL THEN
         LET nulls = nulls + 1
      END IF
   END FOR
   CALL Assertions.assertEqualsInt(500, nulls, "rate 100 always yields NULL")
END FUNCTION

PRIVATE FUNCTION testNullByDefault() RETURNS ()
   VAR i INTEGER
   VAR nulls INTEGER = 0
   CALL Fuzz.seed(3)
   FOR i = 1 TO 2000
      IF Fuzz.nextInt(1, 6) IS NULL THEN
         LET nulls = nulls + 1
      END IF
   END FOR
   # 5 percent of 2000 is 100; allow a wide band, the point is "sometimes".
   CALL Assertions.assertTrue(nulls >= 40 AND nulls <= 200,
      SFMT("expected about 100 NULLs in 2000 draws, got %1", nulls))
END FUNCTION

PRIVATE FUNCTION testStringLength() RETURNS ()
   VAR i INTEGER
   VAR text STRING
   VAR longest INTEGER = 0
   CALL Fuzz.seed(4)
   CALL Fuzz.setNullRate(0)
   FOR i = 1 TO 1000
      LET text = Fuzz.nextString(10)
      CALL Assertions.assertNotNull(text, "a string is generated")
      CALL Assertions.assertTrue(text.getLength() <= 10,
         SFMT("length %1 exceeds 10", text.getLength()))
      IF text.getLength() > longest THEN
         LET longest = text.getLength()
      END IF
   END FOR
   CALL Assertions.assertEqualsInt(10, longest, "the maximum length is reached")
END FUNCTION

PRIVATE FUNCTION testStringAwkward() RETURNS ()
   VAR i INTEGER
   VAR text STRING
   VAR sawQuote BOOLEAN = FALSE
   VAR sawBlank BOOLEAN = FALSE
   CALL Fuzz.seed(5)
   CALL Fuzz.setNullRate(0)
   FOR i = 1 TO 2000
      LET text = Fuzz.nextString(40)
      IF text.getIndexOf("'", 1) > 0 THEN
         LET sawQuote = TRUE
      END IF
      IF text.getLength() > 0 AND text.trim().getLength() == 0 THEN
         LET sawBlank = TRUE
      END IF
   END FOR
   CALL Assertions.assertTrue(sawQuote, "a single quote is generated")
   CALL Assertions.assertTrue(sawBlank, "a blanks-only string is generated")
END FUNCTION

PRIVATE FUNCTION testSmallSize() RETURNS ()
   VAR i INTEGER
   VAR n INTEGER
   VAR text STRING
   VAR d DATE
   VAR x DECIMAL(32,10)
   VAR used INTEGER
   LET used = Fuzz.begin(7, 5)
   CALL Fuzz.setNullRate(0)
   FOR i = 1 TO 300
      LET n = Fuzz.nextInt(-1000000, 1000000)
      CALL Assertions.assertTrue(n >= -5 AND n <= 5, SFMT("int %1 at size 5", n))
      LET x = Fuzz.nextDecimal(-1000000, 1000000)
      CALL Assertions.assertTrue(x >= -5 AND x <= 5, SFMT("decimal %1 at size 5", x))
      LET d = Fuzz.nextDate()
      CALL Assertions.assertTrue(d >= MDY(1, 1, 2000) - 5 AND d <= MDY(1, 1, 2000) + 5,
         SFMT("date %1 at size 5", d))
      LET text = Fuzz.nextString(50)
      CALL Assertions.assertTrue(text.getLength() <= 5, "string at size 5")
      CALL Assertions.assertTrue(Fuzz.nextCount(50) <= 5, "count at size 5")
   END FOR
   LET used = Fuzz.begin(7, 0)
   CALL Fuzz.setNullRate(0)
   CALL Assertions.assertNull(Fuzz.nextString(50), "size 0 has no room for a string")
   CALL Assertions.assertEqualsInt(0, Fuzz.nextInt(-1000000, 1000000), "size 0 int is 0")
   CALL Assertions.assertEqualsInt(0, Fuzz.nextCount(50), "size 0 count is 0")
END FUNCTION

PRIVATE FUNCTION testDate() RETURNS ()
   VAR i INTEGER
   VAR d DATE
   VAR sawMax BOOLEAN = FALSE
   VAR sawLeap BOOLEAN = FALSE
   CALL Fuzz.seed(8)
   CALL Fuzz.setNullRate(0)
   FOR i = 1 TO 1000
      LET d = Fuzz.nextDate()
      CALL Assertions.assertNotNull(d, "a date is generated")
      CALL Assertions.assertTrue(d >= MDY(1, 1, 1) AND d <= MDY(12, 31, 9999),
         SFMT("date %1 out of range", d))
      IF d = MDY(12, 31, 9999) THEN
         LET sawMax = TRUE
      END IF
      IF d = MDY(2, 29, 2000) OR d = MDY(2, 29, 2024) THEN
         LET sawLeap = TRUE
      END IF
   END FOR
   CALL Assertions.assertTrue(sawMax, "31/12/9999 is generated")
   CALL Assertions.assertTrue(sawLeap, "29 February is generated")
END FUNCTION

PRIVATE FUNCTION testDecimal() RETURNS ()
   VAR i INTEGER
   VAR x DECIMAL(32,10)
   VAR sawStep BOOLEAN = FALSE
   CALL Fuzz.seed(9)
   CALL Fuzz.setNullRate(0)
   FOR i = 1 TO 1000
      LET x = Fuzz.nextDecimal(-1, 1)
      CALL Assertions.assertNotNull(x, "a decimal is generated")
      CALL Assertions.assertTrue(x >= -1 AND x <= 1, SFMT("decimal %1 out of range", x))
      IF x = 0.0000000001 THEN
         LET sawStep = TRUE
      END IF
   END FOR
   CALL Assertions.assertTrue(sawStep, "the smallest step is generated")
END FUNCTION

PRIVATE FUNCTION testCount() RETURNS ()
   VAR i INTEGER
   VAR n INTEGER
   VAR sawZero BOOLEAN = FALSE
   VAR sawMax BOOLEAN = FALSE
   CALL Fuzz.seed(10)
   FOR i = 1 TO 500
      LET n = Fuzz.nextCount(5)
      CALL Assertions.assertNotNull(n, "a count is never NULL")
      CALL Assertions.assertTrue(n >= 0 AND n <= 5, SFMT("count %1", n))
      IF n = 0 THEN
         LET sawZero = TRUE
      END IF
      IF n = 5 THEN
         LET sawMax = TRUE
      END IF
   END FOR
   CALL Assertions.assertTrue(sawZero, "an empty array is generated")
   CALL Assertions.assertTrue(sawMax, "a full array is generated")
END FUNCTION

PRIVATE FUNCTION testBoolean() RETURNS ()
   VAR i INTEGER
   VAR b BOOLEAN
   VAR sawTrue BOOLEAN = FALSE
   VAR sawFalse BOOLEAN = FALSE
   CALL Fuzz.seed(11)
   CALL Fuzz.setNullRate(0)
   FOR i = 1 TO 200
      LET b = Fuzz.nextBoolean()
      IF b THEN
         LET sawTrue = TRUE
      ELSE
         LET sawFalse = TRUE
      END IF
   END FOR
   CALL Assertions.assertTrue(sawTrue AND sawFalse, "both values are generated")
END FUNCTION

PRIVATE FUNCTION testTrace() RETURNS ()
   VAR text STRING
   VAR n INTEGER
   LET n = Fuzz.begin(12, Fuzz.cFullSize)
   CALL Assertions.assertNull(Fuzz.getTrace(), "nothing drawn yet")
   CALL Fuzz.setNullRate(0)
   LET n = Fuzz.nextInt(7, 7)
   LET text = Fuzz.nextString(3)
   CALL Assertions.assertContains(Fuzz.getTrace(), "int=7", "the int is traced")
   CALL Assertions.assertContains(Fuzz.getTrace(), "str=", "the string is traced")
   LET n = Fuzz.begin(12, Fuzz.cFullSize)
   CALL Assertions.assertNull(Fuzz.getTrace(), "begin() clears the trace")
END FUNCTION

PRIVATE FUNCTION testUnseeded() RETURNS ()
   # A test that never calls seed() or begin() still gets a defined stream.
   CALL Assertions.assertNotNull(Fuzz.nextCount(3), "usable without a seed")
END FUNCTION

PRIVATE FUNCTION testBeginHugeSeed() RETURNS ()
   VAR used INTEGER
   VAR replayed INTEGER
   VAR first STRING
   # 2^63 - 1: adding the modulus before reducing used to overflow the
   # BIGINT, and the NULL that came back restarted the generator at seed 1
   # and full size.
   LET used = Fuzz.begin(9223372036854775807, 7)
   CALL Assertions.assertNotNull(used, "a seed near 2^63 is folded, not lost")
   CALL Assertions.assertTrue(used >= 1 AND used <= 2147483646,
      SFMT("seed folded to %1", used))
   CALL Assertions.assertEqualsInt(7, Fuzz.getSize(), "the requested size is kept")
   LET first = drawMixed(50)
   LET replayed = Fuzz.begin(used, 7)
   CALL Assertions.assertEquals(first, drawMixed(50), "the returned seed replays the run")
   CALL Assertions.assertEqualsInt(used, replayed, "folding the returned seed changes nothing")
   LET used = Fuzz.begin(9223372036854775000, 9)
   CALL Assertions.assertNotNull(used, "so is a seed a few hundred below it")
   CALL Assertions.assertEqualsInt(9, Fuzz.getSize(), "and its size is kept")
END FUNCTION

PRIVATE FUNCTION testStringTabNewline() RETURNS ()
   VAR i INTEGER
   VAR mixed STRING
   VAR seen BOOLEAN = FALSE
   # A comma list: ASCII is a prefix operator that swallows the rest of a
   # || chain, so the same text written with || is "a ".
   LET mixed = "a", ASCII 9, "b", ASCII 10, "c"
   CALL Assertions.assertEqualsInt(5, mixed.getLength(), "the expected string has five characters")
   CALL Fuzz.seed(5)
   CALL Fuzz.setNullRate(0)
   FOR i = 1 TO 2000
      IF Fuzz.nextString(40) == mixed THEN
         LET seen = TRUE
      END IF
   END FOR
   CALL Assertions.assertTrue(seen, "a string with a tab and a newline between letters is generated")
END FUNCTION

PRIVATE FUNCTION testSeedsIndependent() RETURNS ()
   VAR thisRun DYNAMIC ARRAY OF INTEGER
   VAR nextRun DYNAMIC ARRAY OF INTEGER
   VAR roll INTEGER
   VAR s INTEGER
   VAR used INTEGER
   VAR chi DECIMAL(20,4)
   # The runner gives consecutive seeds to consecutive runs. Without a
   # scramble run k + 1 draws the values of run k plus a constant, and this
   # statistic is about 3000; independent runs give about 25.
   FOR s = 1 TO 3601
      LET used = Fuzz.begin(s, Fuzz.cFullSize)
      CALL Fuzz.setNullRate(0)
      LET roll = Fuzz.nextInt(1, 6)
      IF s <= 3600 THEN
         LET thisRun[s] = roll
      END IF
      IF s >= 2 THEN
         LET nextRun[s - 1] = roll
      END IF
   END FOR
   LET chi = independence(thisRun, nextRun)
   CALL Assertions.assertTrue(chi < 60, SFMT("run k and run k + 1 are dependent: chi-square %1", chi))
END FUNCTION

PRIVATE FUNCTION testDrawsIndependent() RETURNS ()
   VAR first DYNAMIC ARRAY OF INTEGER
   VAR second DYNAMIC ARRAY OF INTEGER
   VAR s INTEGER
   VAR used INTEGER
   VAR chi DECIMAL(20,4)
   FOR s = 1 TO 3600
      LET used = Fuzz.begin(s, Fuzz.cFullSize)
      CALL Fuzz.setNullRate(0)
      LET first[s] = Fuzz.nextInt(1, 6)
      LET second[s] = Fuzz.nextInt(1, 6)
   END FOR
   LET chi = independence(first, second)
   CALL Assertions.assertTrue(chi < 60, SFMT("two draws of one run are dependent: chi-square %1", chi))
END FUNCTION

# Parametrized and fuzz entry points ----------------------------------

PRIVATE FUNCTION checkIntInBounds(args util.JSONObject) RETURNS ()
   VAR bound tBound
   VAR i INTEGER
   VAR n INTEGER
   CALL args.toFGL(bound)
   CALL Assertions.assertNotNull(bound.lowest, "the row carries lowest")
   CALL Assertions.assertNotNull(bound.highest, "the row carries highest")
   CALL Fuzz.seed(bound.lowest)
   CALL Fuzz.setNullRate(0)
   FOR i = 1 TO 100
      LET n = Fuzz.nextInt(bound.lowest, bound.highest)
      CALL Assertions.assertTrue(n >= bound.lowest AND n <= bound.highest,
         SFMT("%1 is outside %2 .. %3", n, bound.lowest, bound.highest))
   END FOR
END FUNCTION

PRIVATE FUNCTION fuzzStringLength() RETURNS ()
   VAR cap INTEGER
   VAR text STRING
   CALL Fuzz.setNullRate(0)
   LET cap = Fuzz.nextInt(1, 40)
   LET text = Fuzz.nextString(cap)
   IF text IS NOT NULL THEN
      CALL Assertions.assertTrue(text.getLength() <= cap,
         SFMT("length %1 exceeds maxLength %2", text.getLength(), cap))
   END IF
END FUNCTION
