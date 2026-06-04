# Self-tests for the Aggregator merge core (Spec 0001, Part B).

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL com.fourjs.fglunit.Aggregator

MAIN
    CALL CliArgs.parse()
    CALL FglUnit.suite("Aggregator")

    CALL FglUnit.register("parses_suite_attributes",  FUNCTION test_parses_suite_attributes)
    CALL FglUnit.register("strips_xml_declaration",   FUNCTION test_strips_xml_declaration)
    CALL FglUnit.register("invalid_xml_is_invalid",   FUNCTION test_invalid_xml_is_invalid)
    CALL FglUnit.register("empty_xml_is_invalid",     FUNCTION test_empty_xml_is_invalid)
    CALL FglUnit.register("crashed_suite_is_an_error", FUNCTION test_crashed_suite_is_an_error)
    CALL FglUnit.register("totals_sum_across_suites", FUNCTION test_totals_sum_across_suites)
    CALL FglUnit.register("render_wraps_in_testsuites", FUNCTION test_render_wraps_in_testsuites)
    CALL FglUnit.register("render_sums_root_totals",  FUNCTION test_render_sums_root_totals)

    EXIT PROGRAM FglUnit.run()
END MAIN

# Helpers -----------------------------------------------------------

PRIVATE FUNCTION sampleSuite(name STRING, tests INTEGER, failures INTEGER,
                             errors INTEGER, skipped INTEGER, tm STRING) RETURNS STRING
    RETURN SFMT("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<testsuite name=\"%1\" tests=\"%2\" failures=\"%3\" errors=\"%4\" skipped=\"%5\" time=\"%6\"><testcase name=\"t\" classname=\"%1\" time=\"%6\"/></testsuite>",
        name, tests, failures, errors, skipped, tm)
END FUNCTION

# Tests -------------------------------------------------------------

PUBLIC FUNCTION test_parses_suite_attributes()
    DEFINE s Aggregator.SuiteSummary
    LET s = Aggregator.parseSuiteXml(sampleSuite("Calc", 3, 1, 0, 2, "0.012"))
    CALL Assertions.assertTrue(s.valid, "valid suite parses")
    CALL Assertions.assertEquals("Calc", s.name, "name attr")
    CALL Assertions.assertEqualsInt(3, s.tests, "tests attr")
    CALL Assertions.assertEqualsInt(1, s.failures, "failures attr")
    CALL Assertions.assertEqualsInt(0, s.errors, "errors attr")
    CALL Assertions.assertEqualsInt(2, s.skipped, "skipped attr")
    CALL Assertions.assertEquals("0.012", s.timeSec, "time attr")
END FUNCTION

PUBLIC FUNCTION test_strips_xml_declaration()
    DEFINE s Aggregator.SuiteSummary
    LET s = Aggregator.parseSuiteXml(sampleSuite("Calc", 1, 0, 0, 0, "0"))
    CALL Assertions.assertNotContains(s.xml, "<?xml", "declaration stripped from element")
    CALL Assertions.assertContains(s.xml, "<testsuite", "element retained")
    CALL Assertions.assertContains(s.xml, "</testsuite>", "element closed")
END FUNCTION

PUBLIC FUNCTION test_invalid_xml_is_invalid()
    DEFINE s Aggregator.SuiteSummary
    LET s = Aggregator.parseSuiteXml("this is not xml <<<")
    CALL Assertions.assertFalse(s.valid, "garbage is not valid")
END FUNCTION

PUBLIC FUNCTION test_empty_xml_is_invalid()
    DEFINE s Aggregator.SuiteSummary
    LET s = Aggregator.parseSuiteXml("")
    CALL Assertions.assertFalse(s.valid, "empty is not valid")
END FUNCTION

PUBLIC FUNCTION test_crashed_suite_is_an_error()
    DEFINE s Aggregator.SuiteSummary
    LET s = Aggregator.crashedSuite("BoomSuite", "exit 134: abend\nstack...")
    CALL Assertions.assertTrue(s.valid, "synthesized suite is usable")
    CALL Assertions.assertEqualsInt(1, s.errors, "counts as one error")
    CALL Assertions.assertEqualsInt(1, s.tests, "one synthetic testcase")
    CALL Assertions.assertContains(s.xml, "<error", "carries an <error> element")
    CALL Assertions.assertContains(s.xml, "BoomSuite", "names the suite")
END FUNCTION

PUBLIC FUNCTION test_totals_sum_across_suites()
    DEFINE arr DYNAMIC ARRAY OF Aggregator.SuiteSummary
    DEFINE t Aggregator.Totals
    LET arr[1] = Aggregator.parseSuiteXml(sampleSuite("A", 3, 1, 0, 0, "0.01"))
    LET arr[2] = Aggregator.parseSuiteXml(sampleSuite("B", 2, 0, 1, 1, "0.02"))
    LET t = Aggregator.totals(arr)
    CALL Assertions.assertEqualsInt(2, t.suites, "two suites")
    CALL Assertions.assertEqualsInt(5, t.tests, "3+2 tests")
    CALL Assertions.assertEqualsInt(1, t.failures, "1 failure")
    CALL Assertions.assertEqualsInt(1, t.errors, "1 error")
    CALL Assertions.assertEqualsInt(1, t.skipped, "1 skipped")
END FUNCTION

PUBLIC FUNCTION test_render_wraps_in_testsuites()
    DEFINE arr DYNAMIC ARRAY OF Aggregator.SuiteSummary
    DEFINE out STRING
    LET arr[1] = Aggregator.parseSuiteXml(sampleSuite("A", 1, 0, 0, 0, "0.01"))
    LET arr[2] = Aggregator.parseSuiteXml(sampleSuite("B", 1, 0, 0, 0, "0.02"))
    LET out = Aggregator.renderSuites(arr)
    CALL Assertions.assertContains(out, "<?xml", "has declaration")
    CALL Assertions.assertContains(out, "<testsuites ", "has testsuites root")
    CALL Assertions.assertContains(out, "</testsuites>", "closes root")
    CALL Assertions.assertContains(out, "name=\"A\"", "embeds suite A")
    CALL Assertions.assertContains(out, "name=\"B\"", "embeds suite B")
END FUNCTION

PUBLIC FUNCTION test_render_sums_root_totals()
    DEFINE arr DYNAMIC ARRAY OF Aggregator.SuiteSummary
    DEFINE out STRING
    LET arr[1] = Aggregator.parseSuiteXml(sampleSuite("A", 3, 1, 0, 0, "0.010"))
    LET arr[2] = Aggregator.parseSuiteXml(sampleSuite("B", 2, 0, 1, 1, "0.020"))
    LET out = Aggregator.renderSuites(arr)
    CALL Assertions.assertContains(out, "tests=\"5\"", "root sums tests")
    CALL Assertions.assertContains(out, "failures=\"1\"", "root sums failures")
    CALL Assertions.assertContains(out, "errors=\"1\"", "root sums errors")
    CALL Assertions.assertContains(out, "skipped=\"1\"", "root sums skipped")
END FUNCTION
