# This file is part of MOLGW
# Author: Fabien Bruneval

-include ./my_machine.arch
-include ./src/my_machine.arch

PREFIX ?=
PYTHON ?= python3

.PHONY: test clean archive tarball archive install

molgw: $(wildcard src/*.f90) $(wildcard src/*.yaml) $(wildcard src/*.py) $(wildcard src/noft/*.F90)
	cd src && $(MAKE)

test:
	cd tests && $(PYTHON) ./run_testsuite.py --keep

clean:
	cd src && $(MAKE) clean

tarball:
	cd src && $(MAKE) tarball

archive:
	cd src && $(MAKE) archive

install: molgw
	mkdir -p $(PREFIX)/bin
	cp -u molgw $(PREFIX)/bin/molgw
	cp -rp basis $(PREFIX)/basis
	mkdir -p $(PREFIX)/utils
	cp -rp utils/*.py $(PREFIX)/utils

#uninstall:
#	$(RM) -r $(PREFIX)

