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

# SOURCES globs every .4gl under the package — including the fglunit_gen /
# fglunit_run program modules, which carry PACKAGE so they self-place here.
build: $(MODULES)

$(PKG_PATH)/%.42m: $(PKG_PATH)/%.4gl
	fglcomp -M -Wall $<

test: build
	$(MAKE) -C tests
	$(MAKE) -C examples

pack:
	fglpkg pack --list

# fglunit supports Genero BDL 4.00 and newer (util.Regexp and
# STRING.replaceAll both arrived in 4.00). The package ships compiled
# .42m modules, and fglpkg fans out one variant per Genero major at
# publish time — but only for the toolchains present on the publishing
# machine. Publish from an environment carrying 4.x, 5.x AND 6.x, or the
# upload silently covers only the version you happen to have installed.
# `fglpkg pack --list` names the variant it built; check it before
# publishing.
publish-dry:
	fglpkg publish --dry-run

clean:
	find . -name '*.42?' -delete
	rm -rf .fglpkg fglpkg.lock

.PHONY: all build test pack publish-dry clean
