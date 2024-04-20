import 'dart:convert';
import 'dart:io';

import 'package:rl_tools/src/cli/processor.dart';
import 'package:rl_tools/src/cli/util.dart';
import 'package:yaml/yaml.dart';

void _usage() {
  stderr.writeln("Usage: $getOurExecutableName() [--dir folder] [--fix]");
  exit(2);
}

void _fatal(String message) {
  stderr.writeln(message);
  exit(2);
}

bool verbose = false;
bool fix = false;
int errorCount = 0;
int nonFixableErrors = 0;
late String baseFolder;
late String projectName;
late String pathPrefix;
late String pathSourcePrefix;

void _error(String message) {
  stderr.writeln("Error: $message");
  errorCount++;
}

void _warn(String message) {
  stderr.writeln("Warning: $message");
}

String formRelativePath(String path) {
  path = path.substring(baseFolder.length + 1);
  var parts = path.split("/");
  var s = "";
  for (var i = 0; i < parts.length - 1; i++) {
    s += "../";
  }
  return s + parts[0];
}

void _examine(String fileName) {
  if (verbose) {
    print("Examining $fileName ...");
  }
  var file = File(fileName);
  var content = file.readAsStringSync();
  var splitter = LineSplitter();
  var lines = splitter.convert(content);
  int lineNumber = 1;
  int count = 0;
  for (var line in lines) {
    bool fixable = false;
    if (line.contains(pathPrefix)) {
      if (line.contains(pathSourcePrefix)) {
        if (fix) {
          _warn("$fileName:$lineNumber: $line");
          count++;
          continue;
        }
        fixable = true;
      }

      _error("$fileName:$lineNumber: $line");
      if (!fixable) {
        nonFixableErrors++;
      }
    }
    lineNumber++;
  }
  if (fix && count > 0) {
    var relativePath = formRelativePath(fileName);
    content = content.replaceAll(pathSourcePrefix, "$relativePath/");
    print("Saving $fileName ...");
    file.writeAsStringSync(content);
  }
}

void resolveProject(Directory folder) {
  String yaml = readFileInDir(folder, "pubspec.yaml");
  var m = loadYaml(yaml);
  String name = m["name"];
  projectName = name;
  pathPrefix = "package:$name/";
  pathSourcePrefix = "${pathPrefix}src/";
}

void _run(String folder) {
  var dir = Directory(folder);
  if (getName(dir) == "test") {
    return;
  }
    if (!dir.existsSync()) {
    _fatal("Folder $folder does not exist.");
  }

  if (verbose) {
    print("Checking folder $folder ...");
  }

  var list = dir.listSync();
  for (var entry in list) {
    if (entry is Directory) {
      _run(entry.path);
    } else {
      if (entry.path.endsWith(".dart")) {
        _examine(entry.path);
      }
    }
  }
}

void main(List<String> args) {
  var cli = CommandLineProcessor(args, usage: _usage);
  baseFolder = cli.findOptionalArgPlusOne("--dir") ?? ".";
  verbose = cli.hasOptionalArg("-v");
  fix = cli.hasOptionalArg("--fix");
  cli.assertNoMore();

  resolveProject(Directory(baseFolder));

  _run(baseFolder);
  if (errorCount > 0) {
    if (nonFixableErrors == 0) {
      stderr.writeln("Run 'make fix' to fix source files.");
    }
    exit(2);
  }
  exit(0);
}
