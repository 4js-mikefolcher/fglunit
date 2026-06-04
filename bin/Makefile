# fglunit command-line tools (fglunit-gen, fglunit-run).
#
#   make           compile the tools (needs the package built first)
#   make clean     remove .42m

PKG_ROOT = ..
SRCS     = fglunit_gen.4gl fglunit_run.4gl
TGTS     = $(SRCS:.4gl=.42m)

export FGLLDPATH := $(PKG_ROOT):$(FGLLDPATH)

all: $(TGTS)

%.42m: %.4gl
	fglcomp -M -Wall $<

clean:
	rm -f *.42m

.PHONY: all clean
