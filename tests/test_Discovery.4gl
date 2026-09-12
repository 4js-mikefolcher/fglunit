# Self-tests for the Discovery codegen core (Spec 0001, Part A).
#
# Hand-written registration on purpose: this suite bootstraps the very
# discovery mechanism that would otherwise generate it.

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL com.fourjs.fglunit.Discovery

MAIN
    CALL CliArgs.parse()
    CALL FglUnit.suite("Discovery")

    CALL FglUnit.register("finds_tests_in_order",      FUNCTION test_finds_tests_in_order)
    CALL FglUnit.register("detects_all_fixtures",      FUNCTION test_detects_all_fixtures)
    CALL FglUnit.register("absent_fixtures_are_false", FUNCTION test_absent_fixtures_are_false)
    CALL FglUnit.register("skips_line_comments",       FUNCTION test_skips_line_comments)
    CALL FglUnit.register("skips_block_comments",      FUNCTION test_skips_block_comments)
    CALL FglUnit.register("brace_in_string_is_not_a_comment",
        FUNCTION test_brace_in_string_is_not_a_comment)
    CALL FglUnit.register("hash_and_dashes_in_string_survive",
        FUNCTION test_hash_and_dashes_in_string_survive)
    CALL FglUnit.register("escaped_quote_in_string_survives",
        FUNCTION test_escaped_quote_in_string_survives)
    CALL FglUnit.register("ignores_non_test_public",   FUNCTION test_ignores_non_test_public)
    CALL FglUnit.register("case_insensitive_keywords", FUNCTION test_case_insensitive_keywords)
    CALL FglUnit.register("duplicate_test_errors",     FUNCTION test_duplicate_test_errors)
    CALL FglUnit.register("duplicate_fixture_errors",  FUNCTION test_duplicate_fixture_errors)
    CALL FglUnit.register("suite_name_derivation",     FUNCTION test_suite_name_derivation)
    CALL FglUnit.register("render_wires_registrations", FUNCTION test_render_wires_registrations)
    CALL FglUnit.register("render_omits_absent_fixtures", FUNCTION test_render_omits_absent_fixtures)

    EXIT PROGRAM FglUnit.run()
END MAIN

# Helpers -----------------------------------------------------------

PRIVATE FUNCTION ln(s STRING) RETURNS STRING
    RETURN s || "\n"
END FUNCTION

# Tests -------------------------------------------------------------

PUBLIC FUNCTION test_finds_tests_in_order()
    DEFINE src STRING
    DEFINE res Discovery.DiscoveryResult
    LET src = ln("IMPORT FGL whatever")
        || ln("PUBLIC FUNCTION test_alpha()")
        || ln("    DISPLAY 1")
        || ln("END FUNCTION")
        || ln("PUBLIC FUNCTION test_beta()")
        || ln("END FUNCTION")
    LET res = Discovery.parseSource(src)
    CALL Assertions.assertNull(res.errorMsg, "no error expected")
    CALL Assertions.assertEqualsInt(2, res.tests.getLength(), "two tests found")
    CALL Assertions.assertEquals("test_alpha", res.tests[1], "first in source order")
    CALL Assertions.assertEquals("test_beta", res.tests[2], "second in source order")
END FUNCTION

PUBLIC FUNCTION test_detects_all_fixtures()
    DEFINE src STRING
    DEFINE res Discovery.DiscoveryResult
    LET src = ln("PUBLIC FUNCTION setUpSuite() END FUNCTION")
        || ln("PUBLIC FUNCTION tearDownSuite() END FUNCTION")
        || ln("PUBLIC FUNCTION setUp() END FUNCTION")
        || ln("PUBLIC FUNCTION tearDown() END FUNCTION")
        || ln("PUBLIC FUNCTION test_only() END FUNCTION")
    LET res = Discovery.parseSource(src)
    CALL Assertions.assertTrue(res.hasSetup, "setUp detected")
    CALL Assertions.assertTrue(res.hasTeardown, "tearDown detected")
    CALL Assertions.assertTrue(res.hasSetupSuite, "setUpSuite detected")
    CALL Assertions.assertTrue(res.hasTeardownSuite, "tearDownSuite detected")
    CALL Assertions.assertEqualsInt(1, res.tests.getLength(), "one test (fixtures not counted)")
END FUNCTION

PUBLIC FUNCTION test_absent_fixtures_are_false()
    DEFINE res Discovery.DiscoveryResult
    LET res = Discovery.parseSource(ln("PUBLIC FUNCTION test_x() END FUNCTION"))
    CALL Assertions.assertFalse(res.hasSetup, "no setUp")
    CALL Assertions.assertFalse(res.hasTeardown, "no tearDown")
    CALL Assertions.assertFalse(res.hasSetupSuite, "no setUpSuite")
    CALL Assertions.assertFalse(res.hasTeardownSuite, "no tearDownSuite")
END FUNCTION

PUBLIC FUNCTION test_skips_line_comments()
    DEFINE src STRING
    DEFINE res Discovery.DiscoveryResult
    LET src = ln("# PUBLIC FUNCTION test_hash_commented()")
        || ln("-- PUBLIC FUNCTION test_dash_commented()")
        || ln("PUBLIC FUNCTION test_real()  # trailing comment")
        || ln("END FUNCTION")
    LET res = Discovery.parseSource(src)
    CALL Assertions.assertEqualsInt(1, res.tests.getLength(), "only the uncommented test")
    CALL Assertions.assertEquals("test_real", res.tests[1], "real test discovered")
END FUNCTION

PUBLIC FUNCTION test_skips_block_comments()
    DEFINE src STRING
    DEFINE res Discovery.DiscoveryResult
    LET src = ln("{ this block hides")
        || ln("PUBLIC FUNCTION test_hidden()")
        || ln("} PUBLIC FUNCTION test_after_block()")
        || ln("END FUNCTION")
    LET res = Discovery.parseSource(src)
    CALL Assertions.assertEqualsInt(1, res.tests.getLength(), "block-commented test ignored")
    CALL Assertions.assertEquals("test_after_block", res.tests[1], "test after close brace found")
END FUNCTION

# String literals are not comments ---------------------------------
#
# A lone "{" inside a string literal used to open a block comment that
# swallowed the rest of the file: every later test vanished from the
# generated runner, with no error and a zero exit code. Silent test loss
# is the worst failure this tool can have, so these pin it down.

PUBLIC FUNCTION test_brace_in_string_is_not_a_comment()
    DEFINE src STRING
    DEFINE res Discovery.DiscoveryResult
    LET src = ln("PUBLIC FUNCTION test_alpha()")
        || ln("    LET s = \"{\"")
        || ln("END FUNCTION")
        || ln("PUBLIC FUNCTION test_beta()")
        || ln("END FUNCTION")
    LET res = Discovery.parseSource(src)
    CALL Assertions.assertNull(res.errorMsg, "no error expected")
    CALL Assertions.assertEqualsInt(2, res.tests.getLength(),
        "an unmatched brace inside a string must not hide later tests")
    CALL Assertions.assertEquals("test_beta", res.tests[2], "second test survives")
END FUNCTION

PUBLIC FUNCTION test_hash_and_dashes_in_string_survive()
    DEFINE src STRING
    DEFINE res Discovery.DiscoveryResult
    LET src = ln("PUBLIC FUNCTION test_hash()  LET s = \"a#b\"  END FUNCTION")
        || ln("PUBLIC FUNCTION test_dashes() LET s = \"a--b\" END FUNCTION")
        || ln("PUBLIC FUNCTION test_last()   END FUNCTION")
    LET res = Discovery.parseSource(src)
    CALL Assertions.assertEqualsInt(3, res.tests.getLength(),
        "# and -- inside a string are not comment markers")
END FUNCTION

PUBLIC FUNCTION test_escaped_quote_in_string_survives()
    DEFINE src STRING
    DEFINE res Discovery.DiscoveryResult
    # The literal closes on the *unescaped* quote, so the trailing "{"
    # is still inside the string and must not open a block comment.
    LET src = ln("PUBLIC FUNCTION test_alpha()")
        || ln("    LET s = \"say \\\"hi\\\" {\"")
        || ln("END FUNCTION")
        || ln("PUBLIC FUNCTION test_beta() END FUNCTION")
    LET res = Discovery.parseSource(src)
    CALL Assertions.assertEqualsInt(2, res.tests.getLength(),
        "backslash-escaped quotes keep the literal open")
END FUNCTION

PUBLIC FUNCTION test_ignores_non_test_public()
    DEFINE src STRING
    DEFINE res Discovery.DiscoveryResult
    LET src = ln("PUBLIC FUNCTION helper()")
        || ln("END FUNCTION")
        || ln("PRIVATE FUNCTION test_private_not_counted()")
        || ln("END FUNCTION")
    LET res = Discovery.parseSource(src)
    CALL Assertions.assertEqualsInt(0, res.tests.getLength(),
        "non-test public and private test both ignored")
END FUNCTION

PUBLIC FUNCTION test_case_insensitive_keywords()
    DEFINE src STRING
    DEFINE res Discovery.DiscoveryResult
    LET src = ln("public function test_lower()")
        || ln("Public Function Test_Mixed()")
    LET res = Discovery.parseSource(src)
    CALL Assertions.assertEqualsInt(2, res.tests.getLength(),
        "lowercase/mixed keywords and Test* prefix both match")
END FUNCTION

PUBLIC FUNCTION test_duplicate_test_errors()
    DEFINE src STRING
    DEFINE res Discovery.DiscoveryResult
    LET src = ln("PUBLIC FUNCTION test_dup() END FUNCTION")
        || ln("PUBLIC FUNCTION test_dup() END FUNCTION")
    LET res = Discovery.parseSource(src)
    CALL Assertions.assertNotNull(res.errorMsg, "duplicate test name is an error")
    CALL Assertions.assertContains(res.errorMsg, "test_dup", "error names the dup")
END FUNCTION

PUBLIC FUNCTION test_duplicate_fixture_errors()
    DEFINE src STRING
    DEFINE res Discovery.DiscoveryResult
    LET src = ln("PUBLIC FUNCTION setUp() END FUNCTION")
        || ln("PUBLIC FUNCTION setUp() END FUNCTION")
    LET res = Discovery.parseSource(src)
    CALL Assertions.assertNotNull(res.errorMsg, "duplicate fixture is an error")
    CALL Assertions.assertContains(res.errorMsg, "setUp", "error names the fixture")
END FUNCTION

PUBLIC FUNCTION test_suite_name_derivation()
    CALL Assertions.assertEquals("Calculator", Discovery.suiteNameFor("test_Calculator"),
        "strip test_ prefix")
    CALL Assertions.assertEquals("Foo", Discovery.suiteNameFor("testFoo"),
        "strip test prefix")
    CALL Assertions.assertEquals("Plain", Discovery.suiteNameFor("Plain"),
        "leave non-test name as-is")
END FUNCTION

PUBLIC FUNCTION test_render_wires_registrations()
    DEFINE res Discovery.DiscoveryResult
    DEFINE out STRING
    LET res = Discovery.parseSource(
        ln("PUBLIC FUNCTION setUp() END FUNCTION")
        || ln("PUBLIC FUNCTION test_alpha() END FUNCTION"))
    LET out = Discovery.renderRunner("test_Sample", "Sample", res)
    CALL Assertions.assertContains(out, "DO NOT EDIT", "carries do-not-edit header")
    CALL Assertions.assertContains(out, "IMPORT FGL test_Sample", "imports the test module")
    CALL Assertions.assertContains(out, "CALL FglUnit.suite(\"Sample\")", "sets suite name")
    CALL Assertions.assertContains(out, "CALL FglUnit.setSetup(FUNCTION test_Sample.setUp)",
        "wires setUp fixture")
    CALL Assertions.assertContains(out,
        "CALL FglUnit.register(\"test_alpha\", FUNCTION test_Sample.test_alpha)",
        "registers the discovered test")
    CALL Assertions.assertContains(out, "EXIT PROGRAM FglUnit.run()", "runs and exits")
END FUNCTION

PUBLIC FUNCTION test_render_omits_absent_fixtures()
    DEFINE res Discovery.DiscoveryResult
    DEFINE out STRING
    LET res = Discovery.parseSource(ln("PUBLIC FUNCTION test_only() END FUNCTION"))
    LET out = Discovery.renderRunner("test_Sample", "Sample", res)
    CALL Assertions.assertNotContains(out, "setTeardown", "no teardown wired")
    CALL Assertions.assertNotContains(out, "setSetupSuite", "no suite setup wired")
END FUNCTION
