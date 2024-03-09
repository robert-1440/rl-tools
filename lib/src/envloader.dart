import 'dart:io';

import 'package:rl_tools/src/cli/util.dart';

final _macroRegex = RegExp(r'\$\{(.*?)}');

String replaceProperties(String template, Map<String, dynamic> properties) {
  return template.replaceAllMapped(_macroRegex, (match) {
    var key = match.group(1);
    var value = properties[key];
    if (value == null) {
      throw ArgumentError('Property not found: $key');
    }
    return value.toString();
  });
}

class _Instance {
  final Map<String, String> _environment;

  final Set<String> _files = {};

  final List<File> _fileStack = [];

  int errorCount = 0;

  _Instance(this._environment);

  bool add(File file) {
    return _files.add(file.absolute.path);
  }

  void push(File file) {
    _fileStack.add(file);
  }

  void pop() {
    _fileStack.removeLast();
  }

  void addError(String text) {
    errorCount += 1;
    if (_fileStack.isNotEmpty) {
      text = "${_fileStack.last.absolute.path}: $text";
    }
    stderr.writeln(text);
  }
}

void _processInclude(File file, int lineNumber, String line, _Instance instance) {
  int index = line.indexOf(" ");
  if (index > 0) {
    var part = line.substring(index + 1).trim();
    if (part.isNotEmpty) {
      File newFile = File(part);
      if (!newFile.isAbsolute) {
        newFile = File(file.parent.path + Platform.pathSeparator + part);
      }
      if (!instance.add(newFile)) {
        instance.addError("${file.path} line $lineNumber: Recursive !INCLUDE - $line");
        return;
      }
      _processFile(newFile, instance);
      return;
    }
  }
  instance.addError("${file.path} line $lineNumber: Invalid !INCLUDE syntax - $line");
}

void processFile(String fileName, Map<String, String> environment) {
  var file = File(fileName);
  var instance = _Instance(environment);
  _processFile(file, instance);
  if (instance.errorCount > 0) {
    exit(2);
  }
}

void _processFile(File file, _Instance instance) {
  if (!file.existsSync()) {
    instance.addError("File ${file.path} does not exist.");
    return;
  }
  instance.push(file);
  try {
    _parseFile(file, instance);
  } finally {
    instance.pop();
  }
}

class LineParser {
  final List<String> lines;

  int _index = 0;

  LineParser(this.lines);

  String next() {
    return lines[_index++];
  }

  bool hasMore() {
    return _index < lines.length;
  }

  void backup() {
    _index -= 1;
  }
}

String _parseMultiLine(String line, LineParser parser) {
  var buffer = StringBuffer();
  buffer.write(line);
  while (parser.hasMore()) {
    line = parser.next();
    if (line.isNotEmpty && (line.startsWith(' ') || line.startsWith('\t'))) {
      line = line.trim();
      if (line.isEmpty) {
        break;
      }
      buffer.write(line);
    } else {
      break;
    }
  }
  return buffer.toString();
}

void _parseFile(File file, _Instance instance) {
  var lines = file.readAsLinesSync();
  int lineNumber = 0;
  var fileName = file.path;
  var environment = instance._environment;
  var parser = LineParser(lines);
  while (parser.hasMore()) {
    var line = parser.next();

    lineNumber += 1;
    line = line.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith("#")) {
      continue;
    }
    if (line.startsWith("!INCLUDE ")) {
      _processInclude(file, lineNumber, line, instance);
      continue;
    }
    int index = line.indexOf("?=");
    bool conditional;
    int offset;
    if (index < 1) {
      index = line.indexOf("=");
      if (index < 1) {
        instance.addError("$fileName line $lineNumber: Invalid syntax - $line");
        continue;
      }
      conditional = false;
      offset = 1;
    } else {
      conditional = true;
      offset = 2;
    }
    var key = line.substring(0, index).trim();
    var value = checkHomeInPath(line.substring(index + offset).trim());

    if (conditional) {
      if (Platform.environment.containsKey(key) || environment.containsKey(key)) {
        continue;
      }
    }
    if (value.endsWith(r'\')) {
      value = _parseMultiLine(value.substring(0, value.length - 1), parser);
    }
    environment[key] = replaceProperties(value, environment);
  }
}
