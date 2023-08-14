
all: tests

tests:
	@dart test test


build:
	@dart compile exe -o dist/ggrep bin/ggrep.dart
