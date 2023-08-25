DIST=dist/
LIB=lib/
SRC=$(LIB)src/
CLI=$(SRC)cli/

STANDARD=pubspec.yaml $(CLI)processor.dart $(CLI)mapper.dart $(CLI)util.dart

all: tests build

tests:
	@dart test test

ggrep: $(DIST)ggrep

gitcheck: $(DIST)gitcheck

$(DIST)ggrep: $(STANDARD) $(LIB)ggrep.dart
	@dart compile exe -o $(DIST)ggrep bin/ggrep.dart

$(DIST)gitcheck: $(STANDARD) $(LIB)gitcheck.dart
	@dart compile exe -o $(DIST)gitcheck $(LIB)gitcheck.dart

build: ggrep gitcheck
