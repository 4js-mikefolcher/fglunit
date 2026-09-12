PACKAGE com.fourjs.fglunit

IMPORT os

# Internal helpers shared by the fglunit modules and the two tools.
#
# NOT part of the public API. Nothing here is documented in USERGUIDE.md
# and anything may change without notice; these functions are PUBLIC only
# because BDL requires it for cross-module visibility inside the package.
#
# Everything here was previously copy-pasted across two or more of
# Reporter, Aggregator, fglunit_gen and fglunit_run. XML escaping in
# particular existed as two independent copies of the same
# correctness-critical code, which is precisely the kind of thing that
# gets fixed in one copy and not the other.

PUBLIC CONSTANT ANSI_RESET  = "\x1b[0m"
PUBLIC CONSTANT ANSI_GREEN  = "\x1b[32m"
PUBLIC CONSTANT ANSI_RED    = "\x1b[31m"
PUBLIC CONSTANT ANSI_YELLOW = "\x1b[33m"
PUBLIC CONSTANT ANSI_DIM    = "\x1b[2m"

# XML ---------------------------------------------------------------

PUBLIC FUNCTION xmlAttr(v STRING) RETURNS STRING
    RETURN "\"" || xmlEscape(NVL(v, "")) || "\""
END FUNCTION

PUBLIC FUNCTION xmlText(v STRING) RETURNS STRING
    RETURN xmlEscape(NVL(v, ""))
END FUNCTION

PUBLIC FUNCTION xmlEscape(v STRING) RETURNS STRING
    # Strip illegal characters before escaping — escaping cannot rescue
    # them, and they would make the document unparseable.
    LET v = xmlClean(v)
    # `&` MUST come first, else subsequent replacements get re-escaped.
    # replaceAll takes a regex and a replacement; `&`, `<`, `>`, `"`
    # have no regex meaning, so we can pass them literally. The
    # replacement strings also contain no `$`, so they're literal.
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

# Text --------------------------------------------------------------

PUBLIC FUNCTION firstLine(s STRING) RETURNS STRING
    DEFINE nl INTEGER
    IF s IS NULL THEN RETURN "" END IF
    LET nl = s.getIndexOf("\n", 1)
    IF nl == 0 THEN RETURN s END IF
    RETURN s.subString(1, nl - 1)
END FUNCTION

# A NULL subject or suffix is FALSE. Note that in BDL an empty string
# literal IS NULL, so `endsWith(x, "")` takes that branch — there is no
# "every string ends with the empty string" case to handle, because an
# empty suffix cannot be expressed distinctly from NULL.
PUBLIC FUNCTION endsWith(s STRING, suffix STRING) RETURNS BOOLEAN
    DEFINE at INTEGER
    IF s IS NULL OR suffix IS NULL THEN RETURN FALSE END IF
    IF s.getLength() < suffix.getLength() THEN RETURN FALSE END IF
    LET at = s.getLength() - suffix.getLength() + 1
    RETURN s.subString(at, s.getLength()) == suffix
END FUNCTION

PUBLIC FUNCTION printIndented(indent STRING, body STRING)
    DEFINE tok base.StringTokenizer
    LET tok = base.StringTokenizer.create(body, "\n")
    WHILE tok.hasMoreTokens()
        DISPLAY indent, tok.nextToken()
    END WHILE
END FUNCTION

# Insertion sort. Directory listings are small, and BDL's built-in array
# sort support varies by version — this keeps the floor at BDL 4.00.
#
# The bounds test is a separate statement on purpose: BDL does not
# short-circuit AND, so `WHILE j >= 1 AND names[j] > key` still evaluates
# names[0] on the last pass and raises -1326. That only shows up when an
# element has to move to the front, which a directory listing that is
# already alphabetical never triggers.
PUBLIC FUNCTION sortNames(names DYNAMIC ARRAY OF STRING)
    DEFINE i, j INTEGER
    DEFINE key STRING
    FOR i = 2 TO names.getLength()
        LET key = names[i]
        LET j = i - 1
        WHILE j >= 1
            IF names[j] <= key THEN EXIT WHILE END IF
            LET names[j + 1] = names[j]
            LET j = j - 1
        END WHILE
        LET names[j + 1] = key
    END FOR
END FUNCTION

# Seconds, JUnit-style: "0.123".

PUBLIC FUNCTION secondsFromMs(ms INTEGER) RETURNS STRING
    DEFINE secs DECIMAL(18,3)
    LET secs = NVL(ms, 0) / 1000.0
    RETURN formatSeconds(secs)
END FUNCTION

PUBLIC FUNCTION formatSeconds(secs DECIMAL(18,3)) RETURNS STRING
    RETURN NVL(secs, 0) USING "<<<<<<<<<<<<<<<<<&.&&&"
END FUNCTION

# Colour ------------------------------------------------------------

# Wrap `text` in an ANSI sequence when colour is wanted, else return it
# unchanged. The caller passes its own mode so this module stays free of
# a dependency on FglUnit (which imports Reporter, which imports this).
PUBLIC FUNCTION colorize(mode STRING, code STRING, text STRING) RETURNS STRING
    IF NOT useColor(mode) THEN RETURN text END IF
    RETURN code || text || ANSI_RESET
END FUNCTION

# mode is "always" | "never" | "auto" (anything else is treated as auto).
#
# "auto" cannot tell a terminal from a redirect: BDL exposes no isatty,
# so `fglrun suite.42m > log.txt` still gets escape sequences. What it
# can honour is explicit intent —
#
#   NO_COLOR   set to anything  -> off   (https://no-color.org)
#   TERM       unset or "dumb"  -> off
#
# For anything else, pass --color never (fglunit-run already forces it
# on the children it spawns).
PUBLIC FUNCTION useColor(mode STRING) RETURNS BOOLEAN
    DEFINE term STRING

    CASE mode
        WHEN "always" RETURN TRUE
        WHEN "never"  RETURN FALSE
    END CASE

    IF fgl_getenv("NO_COLOR") IS NOT NULL THEN
        RETURN FALSE
    END IF

    LET term = fgl_getenv("TERM")
    IF term IS NULL OR term.getLength() == 0 OR term == "dumb" THEN
        RETURN FALSE
    END IF
    RETURN TRUE
END FUNCTION

# Files -------------------------------------------------------------

PUBLIC FUNCTION readFile(path STRING) RETURNS STRING
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

PUBLIC FUNCTION writeFile(path STRING, text STRING) RETURNS BOOLEAN
    DEFINE ch base.Channel
    LET ch = base.Channel.create()
    TRY
        CALL ch.openFile(path, "w")
    CATCH
        RETURN FALSE
    END TRY
    # Callers terminate every line (including the last) with "\n"; strip
    # one so writeLine doesn't double the trailing newline.
    IF text IS NOT NULL AND text.getLength() > 0
       AND text.getCharAt(text.getLength()) == "\n" THEN
        LET text = text.subString(1, text.getLength() - 1)
    END IF
    CALL ch.writeLine(NVL(text, ""))
    CALL ch.close()
    RETURN TRUE
END FUNCTION

PUBLIC FUNCTION deleteFile(path STRING)
    DEFINE ignored INTEGER
    TRY
        LET ignored = os.Path.delete(path)
    CATCH
    END TRY
END FUNCTION
