# fglunit self-tests
#
#   make           compile + run self-tests (exit 0 on green)
#   make clean     remove .42m

PKG_ROOT = ..
SRCS     = test_Assertions.4gl test_Discovery.4gl test_Aggregator.4gl \
           test_Reporter.4gl test_Internal.4gl test_Fuzz.4gl
FIXTURES = fixture_Lifecycle.42m fixture_Fuzz.42m
TGTS     = $(SRCS:.4gl=.42m)

export FGLLDPATH := $(PKG_ROOT):$(FGLLDPATH)

all: run

# Every suite runs even when an earlier one fails, and make fails at the end:
# a failing suite must not hide the ones after it. test_Reporter, test_Internal
# and test_Fuzz run under both length semantics because the default (BYTE) is
# what a CI runner or a customer machine has, and a developer shell that
# exports CHAR would otherwise hide a BYTE failure in the text handling.
run: $(TGTS) $(FIXTURES)
	@status=0; \
	for suite in test_Assertions test_Discovery test_Aggregator; do \
		echo "fglrun $$suite.42m"; \
		fglrun $$suite.42m || status=1; \
	done; \
	for suite in test_Reporter test_Internal test_Fuzz; do \
		for semantics in BYTE CHAR; do \
			echo "FGL_LENGTH_SEMANTICS=$$semantics fglrun $$suite.42m"; \
			FGL_LENGTH_SEMANTICS=$$semantics fglrun $$suite.42m || status=1; \
		done; \
	done; \
	echo "sh ./integration.sh"; \
	sh ./integration.sh || status=1; \
	exit $$status

%.42m: %.4gl
	fglcomp -M -Wall $<

clean:
	rm -f *.42m fglunit_reporter_*.xml

.PHONY: all run clean
