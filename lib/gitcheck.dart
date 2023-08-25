import 'dart:io';

import 'package:rl_tools/src/cli/exec.dart';
import 'package:rl_tools/src/cli/processor.dart';
import 'package:rl_tools/src/cli/util.dart';

var apply = false;
var verbose = false;

class FolderEntry {
  final Directory directory;

  final Set<String> excludes;

  FolderEntry(this.directory, this.excludes);

  Iterable<Directory> listDirectories() {
    var it = directory.listSync().whereType<Directory>();
    if (excludes.isNotEmpty) {
      it = it.where((d) => !excludes.contains(getName(d)));
    }
    return it;
  }
}

Future<Execution> executeGit(List<String> options) async {
  return execute("git", options);
}

void warn(String message) {
  stderr.writeln("Warning: $message");
}

List<FolderEntry> loadFolderEntries() {
  File f = formHomeFile(".1440/gitcheck/locations");
  if (!f.existsSync()) {
    fatalError("${f.path} does not exist.");
  }
  var homePath = getHomePath();
  String content = f.readAsStringSync();
  var lines = lineSplitter.convert(content);
  List<FolderEntry> dirList = [];
  for (var line in lines) {
    line = line.trim();
    if (line.startsWith("#")) {
      continue;
    }
    line = line.replaceAll("~", homePath);
    int index = line.indexOf(" except ");
    var excludeSet = <String>{};

    if (index > 0) {
      var excludes = line.substring(index + 8);
      var parts = excludes.split(",");
      excludeSet.addAll(parts.map((e) => e.trim()));
      line = line.substring(0, index).trim();
    }
    var dir = Directory(line);
    if (!dir.existsSync()) {
      warn("$line does not exist.");
    } else {
      dirList.add(FolderEntry(dir, excludeSet));
    }
  }
  return dirList;
}

class Status {
  final String branch;

  final List<String> fileList;

  Status(this.branch, this.fileList);
}

Directory? findGitFolder(Directory dir) {
  for (var entry in dir.listSync().whereType<Directory>()) {
    var name = getName(entry);
    if (name == ".git") {
      return entry.parent;
    }
  }
  return null;
}

Future<Status?> gitStatus() async {
  var execution = await executeGit(["status", "-b", "--porcel"]);
  var lines = lineSplitter.convert(execution.stdoutString);
  String? branch;
  List<String> fileList = [];

  for (var line in lines) {
    line = line.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith("## ")) {
      line = line.substring(3);
      int index = line.indexOf(".");
      if (index > 0) {
        line = line.substring(0, index);
      }
      branch = line;
    } else {
      fileList.add(line);
    }
  }
  if (branch == null || fileList.isEmpty) {
    return null;
  }
  return Status(branch, fileList);
}

Future<void> processFolder(Directory dir) async {
  var current = Directory.current;
  Directory.current = dir;

  try {
    if (verbose) {
      print("Checking ${dir.path} ...");
    }
    var status = await gitStatus();
    if (status != null) {
      print("Repo: ${dir.path}");
      print("Branch: ${status.branch}");
      print("Files:");
      for (var f in status.fileList) {
        print("  > $f");
      }
      stdout.writeln();
    } else {
      if (verbose) {
        print(" > No changes.");
      }
    }

  } finally {
    Directory.current = current;
  }
}

Future<void> process(FolderEntry entry) async {
  var list = entry.listDirectories();
  for (var entry in list) {
    var gitFolder = findGitFolder(entry);
    if (gitFolder == null) {
      warn("Cannot find .git folder in ${entry.path}.");
    } else {
      await processFolder(gitFolder);
    }
  }
}

void main(List<String> args) async {
  var cli = CommandLineProcessor(args, usage: "${getOurExecutableName()} [--apply]");

  apply = cli.hasOptionalArg("--apply");
  verbose = cli.hasOptionalArg("-v") || cli.hasOptionalArg("--v");
  cli.assertNoMore();

  var dirs = loadFolderEntries();
  if (dirs.isEmpty) {
    warn("No locations.");
    exit(0);
  }
  for (var dir in dirs) {
    await process(dir);
  }
}
