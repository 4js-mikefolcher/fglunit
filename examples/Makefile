# Example: Calculator module + test_Calculator suite.
#
#   make           build + run tests
#   make clean     remove .42m

PKG_ROOT = ..
SRCS     = Calculator.4gl test_Calculator.4gl
TGTS     = $(SRCS:.4gl=.42m)

export FGLLDPATH := $(PKG_ROOT):.:$(FGLLDPATH)

all: run

run: $(TGTS)
	fglrun test_Calculator.42m

%.42m: %.4gl
	fglcomp -M -Wall $<

clean:
	rm -f *.42m

.PHONY: all run clean
