# Self-tests for the shared internal helpers.
#
# Internal is not public API, but it is now the single home for the XML
# escaping both writers depend on — the code that, duplicated, produced
# unparseable JUnit documents. It is worth testing directly rather than
# only through a Reporter file round-trip.

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL com.fourjs.fglunit.Internal

MAIN
    CALL CliArgs.parse()
    CALL FglUnit.suite("Internal")

    CALL FglUnit.register("escapes_the_five_xml_metacharacters",
        FUNCTION test_escapes_the_five_xml_metacharacters)
    CALL FglUnit.register("ampersand_is_escaped_first",
        FUNCTION test_ampersand_is_escaped_first)
    CALL FglUnit.register("strips_c0_controls",
        FUNCTION test_strips_c0_controls)
    CALL FglUnit.register("keeps_tab_newline_return",
        FUNCTION test_keeps_tab_newline_return)
    CALL FglUnit.register("keeps_non_ascii_text",
        FUNCTION test_keeps_non_ascii_text)
    CALL FglUnit.register("xmlAttr_quotes_and_escapes",
        FUNCTION test_xmlAttr_quotes_and_escapes)
    CALL FglUnit.register("firstLine_splits_on_newline",
        FUNCTION test_firstLine_splits_on_newline)
    CALL FglUnit.register("endsWith_edge_cases",
        FUNCTION test_endsWith_edge_cases)
    CALL FglUnit.register("sortNames_orders_ascending",
        FUNCTION test_sortNames_orders_ascending)
    CALL FglUnit.register("seconds_formatting",
        FUNCTION test_seconds_formatting)
    CALL FglUnit.register("color_modes_are_absolute",
        FUNCTION test_color_modes_are_absolute)
    CALL FglUnit.register("shellWord_plain_names_are_left_alone",
        FUNCTION test_shellWord_plain_names_are_left_alone)
    CALL FglUnit.register("shellWord_posix_single_quotes",
        FUNCTION test_shellWord_posix_single_quotes)
    CALL FglUnit.register("shellWord_windows_double_quotes",
        FUNCTION test_shellWord_windows_double_quotes)
    CALL FglUnit.register("shellWord_windows_refuses_what_cannot_be_quoted",
        FUNCTION test_shellWord_windows_refuses_what_cannot_be_quoted)

    EXIT PROGRAM FglUnit.run()
END MAIN

# XML ---------------------------------------------------------------

PUBLIC FUNCTION test_escapes_the_five_xml_metacharacters()
    CALL Assertions.assertEquals("&lt;b&gt;", Internal.xmlEscape("<b>"), "angle brackets")
    CALL Assertions.assertEquals("&quot;q&quot;", Internal.xmlEscape("\"q\""), "double quotes")
    CALL Assertions.assertEquals("a&amp;b", Internal.xmlEscape("a&b"), "ampersand")
    # An apostrophe is legal inside a double-quoted attribute, so it is
    # deliberately left alone.
    CALL Assertions.assertEquals("it's", Internal.xmlEscape("it's"), "apostrophe untouched")
END FUNCTION

PUBLIC FUNCTION test_ampersand_is_escaped_first()
    # If "&" were escaped after "<", the "&" of "&lt;" would be escaped
    # again and produce "&amp;lt;".
    CALL Assertions.assertEquals("&amp;lt;", Internal.xmlEscape("&lt;"),
        "already-escaped input is escaped once, not twice")
END FUNCTION

PUBLIC FUNCTION test_strips_c0_controls()
    DEFINE dirty STRING
    # ASCII 0 is deliberately absent: BDL renders it as a space rather
    # than a NUL, so it never reaches the filter as a control character.
    LET dirty = "a", ASCII 1, "b", ASCII 7, "c", ASCII 27, "d", ASCII 12, "e", ASCII 31, "f"
    CALL Assertions.assertEquals("abcdef", Internal.xmlEscape(dirty),
        "C0 controls have no legal XML form and are dropped")
END FUNCTION

PUBLIC FUNCTION test_keeps_tab_newline_return()
    DEFINE ok STRING
    LET ok = "a", ASCII 9, "b", ASCII 10, "c", ASCII 13, "d"
    CALL Assertions.assertEquals(ok, Internal.xmlEscape(ok),
        "tab, LF and CR are legal XML characters")
END FUNCTION

PUBLIC FUNCTION test_keeps_non_ascii_text()
    CALL Assertions.assertEquals("café — naïve", Internal.xmlEscape("café — naïve"),
        "multi-byte characters survive the control-character filter")
END FUNCTION

PUBLIC FUNCTION test_xmlAttr_quotes_and_escapes()
    CALL Assertions.assertEquals("\"a&lt;b\"", Internal.xmlAttr("a<b"), "quoted and escaped")
    CALL Assertions.assertEquals("\"\"", Internal.xmlAttr(NULL), "NULL becomes an empty attribute")
END FUNCTION

# Text --------------------------------------------------------------

PUBLIC FUNCTION test_firstLine_splits_on_newline()
    CALL Assertions.assertEquals("one", Internal.firstLine("one\ntwo\nthree"), "first line only")
    CALL Assertions.assertEquals("solo", Internal.firstLine("solo"), "no newline at all")
    CALL Assertions.assertEquals("", Internal.firstLine(NULL), "NULL becomes empty")
END FUNCTION

PUBLIC FUNCTION test_endsWith_edge_cases()
    CALL Assertions.assertTrue(Internal.endsWith("a.run.42m", ".42m"), "matching suffix")
    CALL Assertions.assertFalse(Internal.endsWith("a.42m", ".4gl"), "different suffix")
    CALL Assertions.assertFalse(Internal.endsWith("x", ".longer"), "suffix longer than subject")
    CALL Assertions.assertFalse(Internal.endsWith(NULL, ".42m"), "NULL subject")
    # In BDL an empty string literal IS NULL, so this is the NULL branch
    # rather than an "empty suffix" one.
    CALL Assertions.assertFalse(Internal.endsWith("abc", ""), "empty suffix is NULL")
END FUNCTION

PUBLIC FUNCTION test_sortNames_orders_ascending()
    DEFINE a DYNAMIC ARRAY OF STRING
    LET a[1] = "charlie"
    LET a[2] = "alpha"
    LET a[3] = "bravo"
    CALL Internal.sortNames(a)
    CALL Assertions.assertEquals("alpha", a[1], "first")
    CALL Assertions.assertEquals("bravo", a[2], "second")
    CALL Assertions.assertEquals("charlie", a[3], "third")
END FUNCTION

PUBLIC FUNCTION test_seconds_formatting()
    CALL Assertions.assertEquals("0.001", Internal.secondsFromMs(1), "one millisecond")
    CALL Assertions.assertEquals("2.004", Internal.secondsFromMs(2004), "two seconds")
    CALL Assertions.assertEquals("0.000", Internal.secondsFromMs(0), "zero")
END FUNCTION

# Colour ------------------------------------------------------------

PUBLIC FUNCTION test_color_modes_are_absolute()
    # "always"/"never" must not consult the environment at all, which is
    # what makes --color never dependable in CI.
    CALL Assertions.assertTrue(Internal.useColor("always"), "always is on")
    CALL Assertions.assertFalse(Internal.useColor("never"), "never is off")
    CALL Assertions.assertEquals("x", Internal.colorize("never", Internal.ANSI_RED, "x"),
        "never returns the text untouched")
    CALL Assertions.assertContains(Internal.colorize("always", Internal.ANSI_RED, "x"),
        "x", "always wraps the text")
END FUNCTION

# Shell quoting for the replay line ----------------------------------
# shellWord takes the platform as a parameter, so the Windows rules are
# tested on every machine. They are tested as strings: how cmd.exe then
# parses them is not something a test on another platform can show.

PRIVATE FUNCTION wordOf(text STRING, windows BOOLEAN) RETURNS STRING
    DEFINE word STRING
    DEFINE exact BOOLEAN
    CALL Internal.shellWord(text, windows) RETURNING word, exact
    RETURN word
END FUNCTION

PRIVATE FUNCTION exactOf(text STRING, windows BOOLEAN) RETURNS BOOLEAN
    DEFINE word STRING
    DEFINE exact BOOLEAN
    CALL Internal.shellWord(text, windows) RETURNING word, exact
    RETURN exact
END FUNCTION

PUBLIC FUNCTION test_shellWord_plain_names_are_left_alone()
    CALL Assertions.assertEquals("badFuzz", wordOf("badFuzz", FALSE), "POSIX")
    CALL Assertions.assertEquals("badFuzz", wordOf("badFuzz", TRUE), "Windows")
    CALL Assertions.assertEquals("a_b.c-d1", wordOf("a_b.c-d1", FALSE), "punctuation that is safe")
    CALL Assertions.assertTrue(exactOf("badFuzz", TRUE), "a plain name is exact")
END FUNCTION

PUBLIC FUNCTION test_shellWord_posix_single_quotes()
    CALL Assertions.assertEquals("'bad prop'", wordOf("bad prop", FALSE), "a space")
    CALL Assertions.assertEquals("'it'\\''s'", wordOf("it's", FALSE),
        "an embedded single quote closes, escapes and reopens")
    CALL Assertions.assertEquals("''\\'''\\'''", wordOf("''", FALSE), "two single quotes in a row")
    CALL Assertions.assertEquals("'$(touch x)'", wordOf("$(touch x)", FALSE), "a command substitution")
    CALL Assertions.assertEquals("'say \"hi\"'", wordOf("say \"hi\"", FALSE), "a double quote is literal")
    CALL Assertions.assertEquals("'100%'", wordOf("100%", FALSE), "a percent sign is literal")
    CALL Assertions.assertEquals("'a\nb'", wordOf("a\nb", FALSE), "a newline is literal inside single quotes")
    CALL Assertions.assertTrue(exactOf("it's", FALSE), "POSIX can always quote")
    CALL Assertions.assertTrue(exactOf("a\nb", FALSE), "even a newline")
END FUNCTION

PUBLIC FUNCTION test_shellWord_windows_double_quotes()
    CALL Assertions.assertEquals("\"bad prop\"", wordOf("bad prop", TRUE), "a space")
    CALL Assertions.assertEquals("\"it's\"", wordOf("it's", TRUE), "a single quote is literal")
    CALL Assertions.assertEquals("\"a\\b\"", wordOf("a\\b", TRUE), "a backslash inside the name is literal")
    CALL Assertions.assertTrue(exactOf("bad prop", TRUE), "a quotable name is exact")
END FUNCTION

PUBLIC FUNCTION test_shellWord_windows_refuses_what_cannot_be_quoted()
    # Each of these has no safe spelling inside double quotes, so the word is
    # a placeholder and `exact` is FALSE: the caller must say so.
    CALL Assertions.assertEquals("NAME", wordOf("say \"hi\"", TRUE), "a double quote")
    CALL Assertions.assertFalse(exactOf("say \"hi\"", TRUE), "a double quote is not exact")
    CALL Assertions.assertFalse(exactOf("100%", TRUE), "a percent sign")
    CALL Assertions.assertFalse(exactOf("a\nb", TRUE), "a line feed")
    CALL Assertions.assertFalse(exactOf("a\rb", TRUE), "a carriage return")
    CALL Assertions.assertFalse(exactOf("dir\\", TRUE),
        "a trailing backslash would escape the closing quote")
    # The same names are fine on POSIX: the refusal is the Windows rule only.
    CALL Assertions.assertTrue(exactOf("say \"hi\"", FALSE), "POSIX quotes a double quote")
    CALL Assertions.assertTrue(exactOf("dir\\", FALSE), "POSIX quotes a trailing backslash")
END FUNCTION
