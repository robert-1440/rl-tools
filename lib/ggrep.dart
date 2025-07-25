import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:rl_tools/src/cli/processor.dart';

var python = false;

var pythonExcludeDirs = {"dist", "virtual-envs", "site-packages"};

bool match(String pattern, String name) {
  if (pattern == "*") {
    return true;
  }
  // If we reach at the end of both strings,
  // we are done
  if (pattern.isEmpty && name.isEmpty) {
    return true;
  }

  // Make sure to eliminate consecutive '*'
  if (pattern.isNotEmpty && pattern[0] == '*') {
    int i = 0;
    while (i + 1 < pattern.length && pattern[i + 1] == '*') {
      i++;
    }
    pattern = pattern.substring(i);
  }

  // Make sure that the characters after '*'
  // are present in second string.
  // This function assumes that the first
  // string will not contain two consecutive '*'
  if (pattern.isNotEmpty && pattern[0] == '*' && name.isEmpty) {
    return false;
  }

  // If the first string contains '?',
  // or current characters of both strings match
  if ((pattern.isNotEmpty && pattern[0] == '?') || (pattern.isNotEmpty && name.isNotEmpty && pattern[0] == name[0])) {
    return match(pattern.substring(1), name.substring(1));
  }

  // If there is *, then there are two possibilities
  // a) We consider current character of second string
  // b) We ignore current character of second string.
  if (pattern.isNotEmpty && pattern[0] == '*') {
    return match(pattern.substring(1), name) || match(pattern, name.substring(1));
  }
  return false;
}

final splitter = LineSplitter();

String getName(String filePath) {
  int index = filePath.lastIndexOf(Platform.pathSeparator);
  if (index > 0) {
    var name = filePath.substring(index + 1);
    if (name.isNotEmpty) {
      return name;
    }
  }
  return filePath;
}

final List<Encoding> encodings = [utf8, latin1, ascii];

String? _decode(Uint8List bytes, Encoding encoding) {
  try {
    return encoding.decode(bytes);
  } on FormatException {
    return null;
  } catch (e) {
    String message = "$e".toLowerCase();
    if (message.contains("decode") || message.contains("unexpected extension")) {
      return null;
    }
    rethrow;
  }
}

String? readFile(FileSystemEntity entity) {
  var bytes = File(entity.path).readAsBytesSync();
  for (var encoding in encodings) {
    var data = _decode(bytes, encoding);
    if (data != null) {
      return data;
    }
  }
  stderr.writeln("WARNING: unable decode read ${entity.path}.");
  return null;
}

bool filterOnSet(FileSystemEntity entity, Set<String> excludeSet) {
  String name = getName(entity.path);
  if (name.startsWith(".") || excludeSet.contains(name)) {
    return false;
  }
  return true;
}

void processDir(RegExp re, String fileMask, bool nameOnly, Directory dir, bool recurse, int? maxChars) {
  List<FileSystemEntity> entries;
  try {
    entries = dir.listSync();
  } on PathAccessException {
    return;
  }
  for (var entry in entries.where((element) => element is Directory || match(fileMask, getName(element.path)))) {
    if (entry is Directory) {
      if (recurse) {
        if (python && !filterOnSet(entry, pythonExcludeDirs)) {
          continue;
        }
        processDir(re, fileMask, nameOnly, entry, recurse, maxChars);
      }
      continue;
    }
    String? data = readFile(entry);
    if (data == null) {
      continue;
    }
    if (re.hasMatch(data)) {
      if (nameOnly) {
        print(entry.path);
      } else {
        int lineNumber = 0;
        for (var line in splitter.convert(data)) {
          lineNumber++;
          var matches = re.allMatches(line);
          if (matches.isEmpty) {
            continue;
          }
          if (maxChars != null && line.length > maxChars) {
            print('> Line $lineNumber:');
            for (var match in matches) {
              final start = max(0, match.start - maxChars);
              final end = min(line.length, match.end + maxChars);
              final snippet = line.substring(start, end);
              print('   ...${snippet.replaceAll('\n', '')}...');
            }
            continue;
          }
          print("${entry.path} $lineNumber: $line");
        }
      }
    }
  }
}

void process(List<String> args) {
  var cli = CommandLineProcessor(args, usage: "Usage: ${getOurExecutableName()} [-rn] [--python] [--max-chars #] pattern filemask");
  var recurse = cli.hasOptionalArg("-r");
  var nameOnly = cli.hasOptionalArg("-n");
  var maxChars = cli.findOptionalArgPlusOneInt("--max-chars");
  python = cli.hasOptionalArg("--python");
  var pattern = cli.next("pattern");
  String fileMask;
  if (python && !cli.hasMore()) {
    fileMask = "*.py";
  } else {
    fileMask = cli.next("filemask");
    cli.assertNoMore();
  }

  var dir = Directory(".");
  var re = RegExp(pattern);
  processDir(re, fileMask, nameOnly, dir, recurse, maxChars);
}
