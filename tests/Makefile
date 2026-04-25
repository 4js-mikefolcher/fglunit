# fglunit self-tests
#
#   make           compile + run self-tests (exit 0 on green)
#   make clean     remove .42m

PKG_ROOT = ..
SRCS     = test_Assertions.4gl
TGTS     = $(SRCS:.4gl=.42m)

export FGLLDPATH := $(PKG_ROOT):$(FGLLDPATH)

all: run

run: $(TGTS)
	fglrun test_Assertions.42m

%.42m: %.4gl
	fglcomp -M -Wall $<

clean:
	rm -f *.42m

.PHONY: all run clean
