import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:rl_tools/src/cli/processor.dart';

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
  } on FormatException catch (e) {
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

void process(List<String> args) {
  var cli = CommandLineProcessor(args, usage: "Usage: ${getOurExecutableName()} [-rn] pattern filemask");
  var recurse = cli.hasOptionalArg("-r");
  var nameOnly = cli.hasOptionalArg("-n");
  var pattern = cli.next("pattern");
  var fileMask = cli.next("filemask");
  cli.assertNoMore();

  var dir = Directory(".");
  var entries = dir.listSync(recursive: recurse);
  var re = RegExp(pattern);
  for (var entry in entries.where((element) => match(fileMask, getName(element.path)))) {
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
          if (re.hasMatch(line)) {
            print("${entry.path} $lineNumber: $line");
          }
        }
      }
    }
  }
}
