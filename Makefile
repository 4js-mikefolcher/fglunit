# fglunit — top-level build
#
#   make           compile the package modules
#   make test      build + run self-tests + run example tests
#   make pack      package for fglpkg publish (prints contents)
#   make publish-dry  fglpkg publish --dry-run
#   make clean     remove compiled artifacts

PKG_PATH  = com/fourjs/fglunit
SOURCES   = $(wildcard $(PKG_PATH)/*.4gl)
MODULES   = $(SOURCES:.4gl=.42m)

export FGLLDPATH := $(CURDIR):$(FGLLDPATH)

all: build

build: $(MODULES)

$(PKG_PATH)/%.42m: $(PKG_PATH)/%.4gl
	fglcomp -M -Wall $<

test: build
	$(MAKE) -C tests
	$(MAKE) -C examples

pack:
	fglpkg pack --list

publish-dry:
	fglpkg publish --dry-run

clean:
	find . -name '*.42?' -delete
	rm -rf .fglpkg fglpkg.lock

.PHONY: all build test pack publish-dry clean
