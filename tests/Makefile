# fglunit self-tests
#
#   make           compile + run self-tests (exit 0 on green)
#   make clean     remove .42m

PKG_ROOT = ..
SRCS     = test_Assertions.4gl test_Discovery.4gl test_Aggregator.4gl \
           test_Reporter.4gl
FIXTURES = fixture_Lifecycle.42m
TGTS     = $(SRCS:.4gl=.42m)

export FGLLDPATH := $(PKG_ROOT):$(FGLLDPATH)

all: run

run: $(TGTS) $(FIXTURES)
	fglrun test_Assertions.42m
	fglrun test_Discovery.42m
	fglrun test_Aggregator.42m
	fglrun test_Reporter.42m
	sh ./integration.sh

%.42m: %.4gl
	fglcomp -M -Wall $<

clean:
	rm -f *.42m fglunit_reporter_*.xml

.PHONY: all run clean
