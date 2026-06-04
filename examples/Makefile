# Example: Calculator module tested with the discovery + aggregation tools.
#
#   make           generate runners, build, run both suites via fglunit-run
#   make clean     remove .42m and generated runners
#
# Requires the package + tools to be built first (the top-level `make build`
# does this; `make test` from the repo root runs the whole chain).

PKG_ROOT = ..
GEN = fglrun $(PKG_ROOT)/bin/fglunit_gen.42m
RUN = fglrun $(PKG_ROOT)/bin/fglunit_run.42m

export FGLLDPATH := $(PKG_ROOT):.:$(FGLLDPATH)

all: run

run:
	# 1. code under test
	fglcomp -M -Wall Calculator.4gl
	# 2. test modules (plain modules: no MAIN, no manual registration)
	fglcomp -M -Wall test_Calculator.4gl
	fglcomp -M -Wall test_MathExtra.4gl
	# 3. generate a runner for each, then compile them
	$(GEN) test_Calculator.4gl test_MathExtra.4gl
	fglcomp -M -Wall test_Calculator.run.4gl
	fglcomp -M -Wall test_MathExtra.run.4gl
	# 4. run both suites through the aggregating driver
	$(RUN) test_Calculator.run.42m test_MathExtra.run.42m

clean:
	rm -f *.42m *.run.4gl

.PHONY: all run clean
