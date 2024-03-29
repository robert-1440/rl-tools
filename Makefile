DIST=dist/
LIB=lib/
SRC=$(LIB)src/
CLI=$(SRC)cli/
BIN=~/bin/

STANDARD=pubspec.yaml $(CLI)processor.dart $(CLI)mapper.dart $(CLI)util.dart

.PHONY: all tests ggrep gitcheck check_imports mkd mkenv ee

all: tests build

tests:
	@dart test test

ggrep: $(BIN)ggrep

gitcheck: $(DIST)gitcheck

mkd: $(BIN)mkd

mkenv: $(BIN)mkenv

ee: $(BIN)ee

check_imports: $(DIST)check_imports

$(DIST)ggrep: $(STANDARD) $(LIB)ggrep.dart
	@dart compile exe -o $(DIST)ggrep bin/ggrep.dart

$(BIN)ggrep: $(DIST)ggrep
	cp $(DIST)ggrep $(BIN)ggrep

$(DIST)gitcheck: $(STANDARD) $(LIB)gitcheck.dart
	@dart compile exe -o $(DIST)gitcheck $(LIB)gitcheck.dart

$(DIST)check_imports: $(STANDARD) $(LIB)check_imports.dart
	@dart compile exe -o $(DIST)check_imports $(LIB)check_imports.dart

$(BIN)mkd: $(STANDARD) $(LIB)mkd.dart
	@dart compile exe -o $(BIN)mkd $(LIB)mkd.dart

$(BIN)mkenv: $(STANDARD) $(LIB)makeenv.dart $(CLI)exec.dart $(CLI)util.dart $(CLI)mapper.dart $(SRC)envloader.dart
	@dart compile exe -o $(BIN)mkenv $(LIB)makeenv.dart

$(BIN)ee: $(STANDARD) $(LIB)exec_env.dart $(CLI)exec.dart $(CLI)util.dart $(CLI)mapper.dart $(SRC)envloader.dart
	@dart compile exe -o $(BIN)ee $(LIB)exec_env.dart

build: ggrep gitcheck check_imports mkd mkenv ee
