PYTHON ?= $(shell if [ -x .venv/bin/python ]; then echo .venv/bin/python; else echo python3; fi)

.PHONY: all build module native test package clean

all: build test

module:
	$(PYTHON) module_system/build_module.py

native:
	$(MAKE) -C native -j4

build: module native

test:
	PYTHONPATH=tests $(PYTHON) -m unittest discover -s tests -v

package: build
	rm -rf dist/CalradiaOnlinePackage
	mkdir -p dist/CalradiaOnlinePackage/export dist/CalradiaOnlinePackage/lua dist/CalradiaOnlinePackage/deploy dist/CalradiaOnlinePackage/bin
	cp module_system/export/*.txt dist/CalradiaOnlinePackage/export/
	cp -r lua/* dist/CalradiaOnlinePackage/lua/
	cp deploy/*.ini deploy/*.txt dist/CalradiaOnlinePackage/deploy/
	cp build/native/* dist/CalradiaOnlinePackage/bin/
	@echo "[CalradiaOnline] Assembled installable package at dist/CalradiaOnlinePackage"

clean:
	$(MAKE) -C native clean
	rm -rf module_system/export dist
