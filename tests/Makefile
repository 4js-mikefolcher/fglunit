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
# a failing suite must not hide the ones after it. That matters most for
# test_Fuzz, which runs under both length semantics because the default (BYTE)
# is what a CI runner or a customer machine has, and a developer shell that
# exports CHAR would otherwise hide a BYTE failure.
run: $(TGTS) $(FIXTURES)
	@status=0; \
	for suite in test_Assertions test_Discovery test_Aggregator test_Reporter test_Internal; do \
		echo "fglrun $$suite.42m"; \
		fglrun $$suite.42m || status=1; \
	done; \
	echo "FGL_LENGTH_SEMANTICS=BYTE fglrun test_Fuzz.42m"; \
	FGL_LENGTH_SEMANTICS=BYTE fglrun test_Fuzz.42m || status=1; \
	echo "FGL_LENGTH_SEMANTICS=CHAR fglrun test_Fuzz.42m"; \
	FGL_LENGTH_SEMANTICS=CHAR fglrun test_Fuzz.42m || status=1; \
	echo "sh ./integration.sh"; \
	sh ./integration.sh || status=1; \
	exit $$status

%.42m: %.4gl
	fglcomp -M -Wall $<

clean:
	rm -f *.42m fglunit_reporter_*.xml

.PHONY: all run clean
