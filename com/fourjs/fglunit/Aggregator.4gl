PACKAGE com.fourjs.fglunit

IMPORT xml

# Aggregator — the merge core behind the `fglunit_run` driver.
#
# Each child test program writes a single-suite JUnit document
# (<testsuite>...). The driver collects those and asks this module to:
#
#   parseSuiteXml(xmlText)        -> SuiteSummary  (one child doc -> counts + element)
#   crashedSuite(name, message)   -> SuiteSummary  (synthesize an errored suite)
#   renderSuites(summaries)       -> STRING        (one <testsuites> document)
#
# Pure string in / string out, so it is unit-tested with fglunit itself
# (see tests/test_Aggregator.4gl). DOM is used only to read attributes and
# to normalize each <testsuite> element; the <testsuites> wrapper is built
# directly so we control the declaration/encoding.

PUBLIC TYPE SuiteSummary RECORD
    valid BOOLEAN,        # FALSE if the child XML could not be parsed
    name STRING,
    tests INTEGER,
    failures INTEGER,
    errors INTEGER,
    skipped INTEGER,
    timeSec STRING,
    xml STRING            # the serialized <testsuite>...</testsuite> element
END RECORD

# Public API --------------------------------------------------------

# Parse one child JUnit document. On malformed XML or a missing/!testsuite
# root, returns a summary with valid = FALSE.
PUBLIC FUNCTION parseSuiteXml(xmlText STRING) RETURNS SuiteSummary
    DEFINE s SuiteSummary
    DEFINE doc xml.DomDocument
    DEFINE root xml.DomNode
    DEFINE full STRING
    DEFINE at INTEGER

    IF xmlText IS NULL OR xmlText.getLength() == 0 THEN
        RETURN s
    END IF

    LET doc = xml.DomDocument.Create()
    TRY
        CALL doc.loadFromString(xmlText)
    CATCH
        RETURN s
    END TRY

    LET root = doc.getDocumentElement()
    IF root IS NULL THEN RETURN s END IF
    IF root.getLocalName() != "testsuite" THEN RETURN s END IF

    LET s.name     = root.getAttribute("name")
    LET s.tests    = toInt(root.getAttribute("tests"))
    LET s.failures = toInt(root.getAttribute("failures"))
    LET s.errors   = toInt(root.getAttribute("errors"))
    LET s.skipped  = toInt(root.getAttribute("skipped"))
    LET s.timeSec  = root.getAttribute("time")

    # Normalize the element via DOM, then drop the <?xml ...?> declaration
    # that saveToString() prepends — keep just the <testsuite> element.
    LET full = doc.saveToString()
    LET at = full.getIndexOf("<testsuite", 1)
    IF at > 0 THEN
        LET s.xml = full.subString(at, full.getLength())
    ELSE
        LET s.xml = full
    END IF

    LET s.valid = TRUE
    RETURN s
END FUNCTION

# Build a one-testcase errored suite for a child that crashed / produced no
# usable JUnit. Counts as an error so the build fails.
PUBLIC FUNCTION crashedSuite(suiteName STRING, message STRING) RETURNS SuiteSummary
    DEFINE s SuiteSummary
    DEFINE sb base.StringBuffer

    LET s.valid    = TRUE
    LET s.name     = NVL(suiteName, "unknown")
    LET s.tests    = 1
    LET s.failures = 0
    LET s.errors   = 1
    LET s.skipped  = 0
    LET s.timeSec  = "0"

    LET sb = base.StringBuffer.create()
    CALL sb.append(SFMT("<testsuite name=%1 tests=\"1\" failures=\"0\" errors=\"1\" skipped=\"0\" time=\"0\">",
        attr(s.name)))
    CALL sb.append(SFMT("<testcase name=\"(suite)\" classname=%1 time=\"0\">", attr(s.name)))
    CALL sb.append(SFMT("<error message=%1>%2</error>",
        attr(firstLine(message)), esc(NVL(message, "suite crashed"))))
    CALL sb.append("</testcase></testsuite>")
    LET s.xml = sb.toString()
    RETURN s
END FUNCTION

# Wrap every suite element in a <testsuites> root with summed totals.
PUBLIC FUNCTION renderSuites(suites DYNAMIC ARRAY OF SuiteSummary) RETURNS STRING
    DEFINE sb base.StringBuffer
    DEFINE i INTEGER
    DEFINE tests, failures, errors, skipped INTEGER
    DEFINE totalTime DECIMAL(18,3)

    LET totalTime = 0   # uninitialized DECIMAL is NULL; NULL + x stays NULL
    FOR i = 1 TO suites.getLength()
        LET tests    = tests    + suites[i].tests
        LET failures = failures + suites[i].failures
        LET errors   = errors   + suites[i].errors
        LET skipped  = skipped  + suites[i].skipped
        LET totalTime = totalTime + toDec(suites[i].timeSec)
    END FOR

    LET sb = base.StringBuffer.create()
    CALL sb.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
    CALL sb.append(SFMT("<testsuites tests=\"%1\" failures=\"%2\" errors=\"%3\" skipped=\"%4\" time=\"%5\">\n",
        tests, failures, errors, skipped, fmtSec(totalTime)))
    FOR i = 1 TO suites.getLength()
        CALL sb.append("  ")
        CALL sb.append(suites[i].xml)
        CALL sb.append("\n")
    END FOR
    CALL sb.append("</testsuites>\n")
    RETURN sb.toString()
END FUNCTION

# Aggregate counters across suites (driver console-summary convenience).
PUBLIC TYPE Totals RECORD
    suites INTEGER,
    tests INTEGER,
    failures INTEGER,
    errors INTEGER,
    skipped INTEGER
END RECORD

PUBLIC FUNCTION totals(suites DYNAMIC ARRAY OF SuiteSummary) RETURNS Totals
    DEFINE t Totals
    DEFINE i INTEGER
    LET t.suites = suites.getLength()
    FOR i = 1 TO suites.getLength()
        LET t.tests    = t.tests    + suites[i].tests
        LET t.failures = t.failures + suites[i].failures
        LET t.errors   = t.errors   + suites[i].errors
        LET t.skipped  = t.skipped  + suites[i].skipped
    END FOR
    RETURN t
END FUNCTION

# Helpers -----------------------------------------------------------

# A child could write a non-numeric attribute (or none). Coercing it
# straight to a number yields NULL, and NULL then poisons every running
# total it is added to — the aggregated report would show blank counts
# rather than one bad suite.
PRIVATE FUNCTION toInt(v STRING) RETURNS INTEGER
    DEFINE n INTEGER
    IF v IS NULL OR v.getLength() == 0 THEN RETURN 0 END IF
    TRY
        LET n = v
    CATCH
        RETURN 0
    END TRY
    IF n IS NULL THEN RETURN 0 END IF
    RETURN n
END FUNCTION

PRIVATE FUNCTION toDec(v STRING) RETURNS DECIMAL(18,3)
    DEFINE d DECIMAL(18,3)
    IF v IS NULL OR v.getLength() == 0 THEN RETURN 0 END IF
    TRY
        LET d = v
    CATCH
        RETURN 0
    END TRY
    IF d IS NULL THEN RETURN 0 END IF
    RETURN d
END FUNCTION

PRIVATE FUNCTION fmtSec(secs DECIMAL(18,3)) RETURNS STRING
    RETURN secs USING "<<<<<<<<<<<<<<<<<&.&&&"
END FUNCTION

PRIVATE FUNCTION attr(v STRING) RETURNS STRING
    RETURN "\"" || esc(NVL(v, "")) || "\""
END FUNCTION

PRIVATE FUNCTION esc(v STRING) RETURNS STRING
    # Strip illegal characters before escaping — see xmlClean below.
    LET v = xmlClean(v)
    LET v = v.replaceAll("&", "&amp;")
    LET v = v.replaceAll("<", "&lt;")
    LET v = v.replaceAll(">", "&gt;")
    LET v = v.replaceAll("\"", "&quot;")
    RETURN v
END FUNCTION

# Drop the characters XML 1.0 forbids outright: the C0 controls other
# than tab, LF and CR. They have no escape form — numeric character
# references are illegal for them too — so the only options are to strip
# them or to emit a document no parser will accept. A failure message
# quoting ANSI-coloured or binary output would otherwise poison the whole
# report, exactly when it is most needed.
#
# NOTE: Reporter.xmlClean is the same function. Keep the two in step.
PRIVATE FUNCTION xmlClean(v STRING) RETURNS STRING
    DEFINE sb base.StringBuffer
    DEFINE i, n INTEGER
    DEFINE c STRING

    LET n = v.getLength()
    LET sb = base.StringBuffer.create()
    FOR i = 1 TO n
        LET c = v.subString(i, i)
        IF c < " " AND c != "\t" AND c != "\n" AND c != "\r" THEN
            CONTINUE FOR
        END IF
        CALL sb.append(c)
    END FOR
    RETURN sb.toString()
END FUNCTION

PRIVATE FUNCTION firstLine(s STRING) RETURNS STRING
    DEFINE nl INTEGER
    IF s IS NULL THEN RETURN "" END IF
    LET nl = s.getIndexOf("\n", 1)
    IF nl == 0 THEN RETURN s END IF
    RETURN s.subString(1, nl - 1)
END FUNCTION
