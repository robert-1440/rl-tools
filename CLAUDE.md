# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Dart-based collection of command-line utilities compiled into standalone executables. The project uses a modular CLI framework with a command-action pattern.

## Development Commands

### Testing
- `dart test test` - Run all tests
- `make tests` - Alternative test command via Makefile

### Building
- `make build` - Build all tools
- `make all` - Run tests and build everything
- Individual tool builds: `make ggrep`, `make csv`, `make mkenv`, etc.

### Code Quality
- Uses `package:lints/recommended.yaml` for static analysis
- Run `dart analyze` for linting

## Architecture

### Core Structure
- **`lib/`** - Main library code for each tool
- **`lib/src/cli/`** - Shared CLI framework with command-action pattern
- **`lib/src/support/`** - Utility modules (CSV processing, etc.)
- **`bin/`** - Entry points that delegate to lib files
- **`dist/`** - Compiled executables

### CLI Framework
The project uses a custom CLI framework in `lib/src/cli/`:
- `cli.dart` - Command/Module/App abstractions
- `processor.dart` - Argument processing
- `mapper.dart` - Parameter mapping utilities
- `util.dart` - Common utilities

Tools follow the pattern: `toolname command action [args]`

### Key Tools
- **ggrep** - Enhanced grep with pattern matching
- **csv** - CSV processing and filtering
- **mkenv/ee** - Environment file management
- **gitcheck** - Git repository utilities
- **mkd** - Directory creation utility
- **zipcmp** - Archive comparison

### Build System
Uses Make with dependency tracking. Each tool compiles to `dist/` then optionally copies to `~/bin/`. The Makefile tracks dependencies on shared CLI components and rebuilds as needed.

## File Patterns
- Main tool implementations: `lib/{toolname}.dart`
- CLI entry points: `bin/{toolname}.dart`
- Shared utilities: `lib/src/cli/` and `lib/src/support/`