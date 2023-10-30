DIST=dist/
LIB=lib/
SRC=$(LIB)src/
CLI=$(SRC)cli/
BIN=~/bin/

STANDARD=pubspec.yaml $(CLI)processor.dart $(CLI)mapper.dart $(CLI)util.dart

all: tests build

tests:
	@dart test test

ggrep: $(BIN)ggrep

gitcheck: $(DIST)gitcheck

check_imports: $(DIST)check_imports

$(DIST)ggrep: $(STANDARD) $(LIB)ggrep.dart
	@dart compile exe -o $(DIST)ggrep bin/ggrep.dart

$(BIN)ggrep: $(DIST)ggrep
	cp $(DIST)ggrep $(BIN)ggrep

$(DIST)gitcheck: $(STANDARD) $(LIB)gitcheck.dart
	@dart compile exe -o $(DIST)gitcheck $(LIB)gitcheck.dart

$(DIST)check_imports: $(STANDARD) $(LIB)check_imports.dart
	@dart compile exe -o $(DIST)check_imports $(LIB)check_imports.dart

build: ggrep gitcheck check_imports
