# Self-tests for the Reporter JUnit writer.
#
# The writer is what CI actually consumes, so the central assertion here
# is that the document PARSES — a report that no reporter can read is
# worse than no report, and it fails exactly when a test failed with
# awkward payload data.

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL com.fourjs.fglunit.Reporter
IMPORT os
IMPORT xml

MAIN
    CALL CliArgs.parse()
    CALL FglUnit.suite("Reporter")

    CALL FglUnit.register("writes_wellformed_document",
        FUNCTION test_writes_wellformed_document)
    CALL FglUnit.register("counts_each_outcome",
        FUNCTION test_counts_each_outcome)
    CALL FglUnit.register("escapes_xml_markup",
        FUNCTION test_escapes_xml_markup)
    CALL FglUnit.register("control_chars_do_not_break_the_document",
        FUNCTION test_control_chars_do_not_break_the_document)
    CALL FglUnit.register("control_chars_in_suite_name_are_stripped",
        FUNCTION test_control_chars_in_suite_name_are_stripped)

    EXIT PROGRAM FglUnit.run()
END MAIN

# Tests -------------------------------------------------------------

PUBLIC FUNCTION test_writes_wellformed_document()
    DEFINE results DYNAMIC ARRAY OF FglUnit.TestResult
    DEFINE out STRING
    CALL addResult(results, "plain", FglUnit.STATUS_PASS, NULL, NULL)
    LET out = writeAndRead(results, "Reporter", "plain")
    CALL Assertions.assertTrue(isWellFormedXml(out), "document must parse")
    CALL Assertions.assertContains(out, "<testsuite ", "has a testsuite root")
    CALL Assertions.assertContains(out, "name=\"plain\"", "names the testcase")
END FUNCTION

PUBLIC FUNCTION test_counts_each_outcome()
    DEFINE results DYNAMIC ARRAY OF FglUnit.TestResult
    DEFINE out STRING
    CALL addResult(results, "ok",      FglUnit.STATUS_PASS,  NULL, NULL)
    CALL addResult(results, "bad",     FglUnit.STATUS_FAIL,  "assertion failed", "at t.4gl:9")
    CALL addResult(results, "boom",    FglUnit.STATUS_ERROR, "-1202: division by zero", NULL)
    CALL addResult(results, "skipped", FglUnit.STATUS_SKIP,  "no database", NULL)
    LET out = writeAndRead(results, "Reporter", "counts")
    CALL Assertions.assertTrue(isWellFormedXml(out), "document must parse")
    CALL Assertions.assertContains(out, "tests=\"4\"",    "counts every testcase")
    CALL Assertions.assertContains(out, "failures=\"1\"", "counts failures")
    CALL Assertions.assertContains(out, "errors=\"1\"",   "counts errors")
    CALL Assertions.assertContains(out, "skipped=\"1\"",  "counts skips")
    CALL Assertions.assertContains(out, "<failure ", "emits a failure element")
    CALL Assertions.assertContains(out, "<error ",   "emits an error element")
    CALL Assertions.assertContains(out, "<skipped ", "emits a skipped element")
END FUNCTION

PUBLIC FUNCTION test_escapes_xml_markup()
    DEFINE results DYNAMIC ARRAY OF FglUnit.TestResult
    DEFINE out STRING
    CALL addResult(results, "markup", FglUnit.STATUS_FAIL,
        "expected <b> & \"quoted\"", "at t.4gl:1")
    LET out = writeAndRead(results, "Reporter", "markup")
    CALL Assertions.assertTrue(isWellFormedXml(out), "document must parse")
    CALL Assertions.assertContains(out, "&lt;b&gt;", "angle brackets escaped")
    CALL Assertions.assertContains(out, "&amp;", "ampersand escaped")
END FUNCTION

# ANSI escapes and other C0 controls have no legal XML representation,
# so they must be stripped rather than embedded or entity-encoded.
PUBLIC FUNCTION test_control_chars_do_not_break_the_document()
    DEFINE results DYNAMIC ARRAY OF FglUnit.TestResult
    DEFINE out, msg STRING
    LET msg = "bell:", ASCII 7, " esc:", ASCII 27, "[31m ff:", ASCII 12, " end"
    CALL addResult(results, "nasty", FglUnit.STATUS_FAIL, msg, "at t.4gl:3")
    LET out = writeAndRead(results, "Reporter", "ctrl")
    CALL Assertions.assertTrue(isWellFormedXml(out),
        "a control character in a failure message must not break the report")
    CALL Assertions.assertNotContains(out, ASCII 7,  "BEL stripped")
    CALL Assertions.assertNotContains(out, ASCII 27, "ESC stripped")
    CALL Assertions.assertNotContains(out, ASCII 12, "FF stripped")
    CALL Assertions.assertContains(out, "bell:", "surrounding text is kept")
    CALL Assertions.assertContains(out, "end", "text after the controls is kept")
END FUNCTION

PUBLIC FUNCTION test_control_chars_in_suite_name_are_stripped()
    DEFINE results DYNAMIC ARRAY OF FglUnit.TestResult
    DEFINE out, suite STRING
    LET suite = "Suite", ASCII 27, "X"
    CALL addResult(results, "ok", FglUnit.STATUS_PASS, NULL, NULL)
    LET out = writeAndRead(results, suite, "suitename")
    CALL Assertions.assertTrue(isWellFormedXml(out),
        "attributes are cleaned as well as element text")
    CALL Assertions.assertNotContains(out, ASCII 27, "ESC stripped from the attribute")
END FUNCTION

# Helpers -----------------------------------------------------------

PRIVATE FUNCTION addResult(results DYNAMIC ARRAY OF FglUnit.TestResult,
                           name STRING, status STRING,
                           message STRING, location STRING)
    DEFINE n INTEGER
    LET n = results.getLength() + 1
    LET results[n].name = name
    LET results[n].status = status
    LET results[n].message = message
    LET results[n].location = location
    LET results[n].durationMs = 1
END FUNCTION

# Write a report to a scratch file, read it back, remove the file.
PRIVATE FUNCTION writeAndRead(results DYNAMIC ARRAY OF FglUnit.TestResult,
                              suiteName STRING, tag STRING) RETURNS STRING
    DEFINE path, text STRING
    DEFINE ignored INTEGER
    LET path = SFMT("fglunit_reporter_%1.xml", tag)
    CALL Reporter.writeJunit(path, suiteName, results)
    LET text = readAll(path)
    TRY
        LET ignored = os.Path.delete(path)
    CATCH
    END TRY
    RETURN text
END FUNCTION

PRIVATE FUNCTION readAll(path STRING) RETURNS STRING
    DEFINE ch base.Channel
    DEFINE sb base.StringBuffer
    DEFINE line STRING
    LET ch = base.Channel.create()
    TRY
        CALL ch.openFile(path, "r")
    CATCH
        RETURN NULL
    END TRY
    LET sb = base.StringBuffer.create()
    WHILE TRUE
        LET line = ch.readLine()
        IF ch.isEof() THEN EXIT WHILE END IF
        CALL sb.append(line)
        CALL sb.append("\n")
    END WHILE
    CALL ch.close()
    RETURN sb.toString()
END FUNCTION

PRIVATE FUNCTION isWellFormedXml(text STRING) RETURNS BOOLEAN
    DEFINE doc xml.DomDocument
    IF text IS NULL OR text.getLength() == 0 THEN
        RETURN FALSE
    END IF
    LET doc = xml.DomDocument.Create()
    TRY
        CALL doc.loadFromString(text)
    CATCH
        RETURN FALSE
    END TRY
    IF doc.getDocumentElement() IS NULL THEN
        RETURN FALSE
    END IF
    RETURN TRUE
END FUNCTION
