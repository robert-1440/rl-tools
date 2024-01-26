import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:uuid/uuid.dart';

final separatorChar = Platform.pathSeparator;

abstract class Mappable {
  Map<String, dynamic> toMap();
}

final lineSplitter = LineSplitter();

class StringBuilder {
  final StringBuffer _sb = StringBuffer();

  StringBuilder([String? initialString]) {
    if (initialString != null) {
      _sb.write(initialString);
    }
  }

  StringBuilder appendLine(dynamic object) {
    return append(object).lineFeed();
  }

  int get length => _sb.length;

  bool get isNotEmpty => _sb.isNotEmpty;

  bool get isEmpty => _sb.isEmpty;

  StringBuilder append(dynamic object) {
    var v = toStringValue(object);
    if (v.isNotEmpty) {
      _sb.write(v);
    }
    return this;
  }

  StringBuilder lineFeed() {
    _sb.writeln();
    return this;
  }

  @override
  String toString() => _sb.toString();
}

class StringIndentWriter {
  final StringBuffer _sb = StringBuffer();

  final String _indentChars;

  String _indent = "";

  int _indentCount = 0;

  bool _needLf = false;

  int _lineLength = 0;

  StringIndentWriter([String? indentChars]) : _indentChars = indentChars ?? "    ";

  void _writeIndent() {
    if (_indentCount > 0) {
      _sb.write(_indent);
    }
  }

  void indent([int count = 1]) {
    if (count > 0) {
      _adjustIndent(count);
    }
  }

  void unIndent([int count = 1]) {
    if (count > 0) {
      _adjustIndent(-count);
    }
  }

  void _adjustIndent(int count) {
    _indentCount = max(0, _indentCount + count);
    if (_indentCount > 0) {
      _indent = _indentChars * _indentCount;
    } else {
      _indent = "";
    }
  }

  void _writeWithLf(String text) {
    if (text.isNotEmpty) {
      _sb.write(text);
    }
    addLf();
  }

  StringIndentWriter addLineFromCurrent(String text) {
    if (_needLf && _lineLength > 0) {
      var current = _indent;
      var count = _indentCount;
      try {
        _indentCount = _lineLength;
        _indent = ' ' * _indentCount;
        addLine(text);
        return this;
      } finally {
        _indent = current;
        _indentCount = count;
      }
    }
    addLine(text);
    return this;
  }

  StringIndentWriter addLine(String text) {
    add("$text\n");
    return this;
  }

  StringIndentWriter addLf() {
    _sb.write('\n');
    _needLf = false;
    return this;
  }

  StringIndentWriter add(String text) {
    var lines = lineSplitter.convert(text);
    var lastLine = lines.removeLast();

    for (var line in lines) {
      if (!_needLf && line.isNotEmpty) {
        _writeIndent();
      }
      _writeWithLf(line);
    }
    if (!_needLf && lastLine.isNotEmpty) {
      _writeIndent();
    }
    if (text.endsWith("\n")) {
      _writeWithLf(lastLine);
    } else {
      _sb.write(lastLine);
      _needLf = true;
      _lineLength = lastLine.length;
    }
    return this;
  }

  @override
  String toString() {
    return _sb.toString();
  }
}

class LayoutBuilder {
  int _maxLen = 0;

  final bool _rightJustifyKeys;

  final String? _separator;

  LayoutBuilder({bool rightJustifyKeys = false, String? separator})
      : _rightJustifyKeys = rightJustifyKeys,
        _separator = separator;

  final List<List<String>> _rows = [];

  void add(String key, dynamic value) {
    if (value == null) {
      value = "null";
    } else if (value is! String) {
      value = value.toString();
    }
    _maxLen = max(key.length, _maxLen);
    _rows.add([key, value]);
  }

  static String formatMap<T>(Map<String, T> map, {bool rightJustifyKeys = false}) {
    var lb = LayoutBuilder();
    for (var entry in map.entries) {
      lb.add(entry.key, entry.value);
    }
    return lb.toString();
  }

  String _pad(String value, int width) {
    return _rightJustifyKeys ? '${value.padLeft(width)} ' : value.padRight(width);
  }

  StringIndentWriter _addKey(String key, StringIndentWriter sw) {
    if (_rightJustifyKeys) {
      key = key.padLeft(_maxLen);
      if (_separator != null) {
        key += _separator!;
      }
    } else {
      if (_separator != null) {
        key += _separator!;
      }
      key = key.padRight(_maxLen);
    }
    sw.add("$key ");
    return sw;
  }

  @override
  String toString({int indentCount = 0, String? indentChars}) {
    var sw = StringIndentWriter(indentChars);
    if (indentCount > 0) {
      sw.indent(indentCount);
    }
    for (var row in _rows) {
      var key = row[0];
      var value = row[1];
      _addKey(key, sw).addLineFromCurrent(value);
    }
    return sw.toString();
  }
}

String lowerCamelCaseToTitle(String name) {
  if (name.isEmpty) {
    return name;
  }
  var sb = StringBuffer();
  sb.write(name[0].toUpperCase());
  for (int i = 1; i < name.length; i++) {
    String c = name[i];
    if (c.toUpperCase() == c) {
      sb.write(' ');
    }
    sb.write(c);
  }
  return sb.toString();
}

class _Column {
  final String key;

  final String dispayValue;

  _Column(this.key, this.dispayValue);
}

String toStringValue(dynamic value) {
  if (value == null) {
    return "";
  }
  if (value is! String) {
    value = value.toString();
  }
  return value;
}

_Cell _toCell(dynamic value) {
  var stringValue = toStringValue(value);
  return _Cell(stringValue, value is int || value is double);
}

class _Cell {
  final String value;

  final bool numeric;

  final int length;

  _Cell(this.value, this.numeric) : length = value.length;

  void format(StringBuffer sb, int width) {
    if (numeric) {
      sb.write(value.padLeft(width));
    } else {
      sb.write(value.padRight(width));
    }
  }
}

class TableBuilder {
  final List<_Column> _columns = [];

  final List<int> _columnLengths = [];

  final List<Map<String, dynamic>> _rows = [];

  late int _cellPadding;

  late String _cellSpacer;

  TableBuilder({int cellPadding = 2}) {
    _cellPadding = max(0, cellPadding);
    if (_cellPadding > 0) {
      _cellSpacer = ' ' * _cellPadding;
    } else {
      _cellSpacer = "";
    }
  }

  TableBuilder addColumn(String key, {String? displayName, bool convertToTitle = false}) {
    displayName ??= key;
    if (convertToTitle) {
      displayName = lowerCamelCaseToTitle(displayName);
    }
    var col = _Column(key, displayName);
    _columnLengths.add(displayName.length);
    _columns.add(col);
    return this;
  }

  TableBuilder addRow(Map<String, dynamic> value) {
    _rows.add(value);
    return this;
  }

  List<Map<String, _Cell>> _generateOutputRows() {
    List<Map<String, _Cell>> outputRows = [];
    for (var row in _rows) {
      int columnIndex = 0;
      Map<String, _Cell> outputRow = {};
      for (var col in _columns) {
        var value = _toCell(row[col.key]);
        outputRow[col.key] = value;
        _columnLengths[columnIndex] = max(_columnLengths[columnIndex], value.length);
        columnIndex++;
      }
      outputRows.add(outputRow);
    }
    return outputRows;
  }

  void _formatHeader(StringBuffer sb) {
    StringBuffer div = StringBuffer();
    int index = 0;
    for (var col in _columns) {
      int width = _columnLengths[index];
      if (index++ > 0) {
        sb.write(_cellSpacer);
        div.write(_cellSpacer);
      }

      sb.write(col.dispayValue.padRight(width));
      div.write('-' * width);
    }
    sb.writeln();
    sb.writeln(div.toString());
  }

  void _formatRow(Map<String, _Cell> row, StringBuffer sb) {
    int index = 0;
    for (var col in _columns) {
      int width = _columnLengths[index];
      if (index++ > 0) {
        sb.write(_cellSpacer);
      }
      var cell = row[col.key];
      if (cell != null) {
        cell.format(sb, width);
      } else {
        sb.write(" " * width);
      }
    }
    sb.writeln();
  }

  String build() {
    if (_columns.isEmpty || _rows.isEmpty) {
      return "";
    }
    var outputRows = _generateOutputRows();
    var sb = StringBuffer();
    _formatHeader(sb);
    for (var row in outputRows) {
      _formatRow(row, sb);
    }
    return sb.toString();
  }
}

String buildTable(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) {
    return "";
  }
  var didColumns = false;
  var tb = TableBuilder();
  for (var row in rows) {
    if (!didColumns) {
      for (var key in row.keys) {
        tb.addColumn(key, convertToTitle: true);
      }
      didColumns = true;
      tb.addRow(row);
    } else {
      tb.addRow(row);
    }
  }
  return tb.build();
}

void showMappableTable(List<Mappable> rows) {
  showTable(rows.map((e) => e.toMap()).toList());
}

void showTable(List<Map<String, dynamic>> rows) {
  print("\n${buildTable(rows)}\n");
}

void showMap<T>(Map<String, T> map,
    {bool rightJustifyKeys = false, String? separator, int lineFeedsBefore = 0, int lineFeedsAfter = 0}) {
  var lb = LayoutBuilder(rightJustifyKeys: rightJustifyKeys, separator: separator);
  for (var entry in map.entries) {
    lb.add(entry.key, entry.value);
  }
  if (lineFeedsBefore > 0) {
    stdout.write('\n' * lineFeedsBefore);
  }

  print(lb.toString());
  if (lineFeedsAfter > 0) {
    stdout.write('\n' * lineFeedsAfter);
  }
}

List<String> splitInTwo(String text, Pattern delimiter) {
  var index = text.indexOf(delimiter);
  if (index > 1) {
    var key = text.substring(0, index).trim();
    var value = text.substring(index + 1).trim();
    return [key, value];
  }
  return [text];
}

String explodeMap(Map<String, dynamic> map, {int indent = 0, bool sort = false}) {
  var lb = LayoutBuilder();
  dynamic keys;
  if (sort) {
    keys = map.keys.toList();
    keys.sort();
  } else {
    keys = map.keys;
  }
  for (var key in keys) {
    lb.add(key, map[key] ?? "");
  }
  return lb.toString(indentCount: indent, indentChars: ' ');
}

String uuid() {
  return Uuid().v4();
}

bool promptYes(String prompt, {int? exitCode}) {
  if (!prompt.contains("?")) {
    prompt += " (Yes)? ";
  } else if (!prompt.endsWith(" ")) {
    prompt += " ";
  }
  for (;;) {
    stdout.write(prompt);
    var input = stdin.readLineSync();
    if (input == null || input.isEmpty) {
      continue;
    }
    if (input.toLowerCase() == "yes") {
      return true;
    }
    if (exitCode != null) {
      exit(exitCode);
    }
    return false;
  }
}

/// Returns the home directory for the current user.
String getHomePath() {
  switch (Platform.operatingSystem) {
    case 'linux':
    case 'macos':
      return Platform.environment['HOME']!;

    case 'windows':
      return Platform.environment['USERPROFILE']!;

    default:
      throw StateError("Unsupported operating system ${Platform.operatingSystem}");
  }
}

File formHomeFile(String name) {
  return File("${getHomePath()}${Platform.pathSeparator}$name");
}

void fatalError(String message) {
  stderr.writeln(message);
  exit(2);
}

String getName(FileSystemEntity entity) {
  var parts = entity.path.split(Platform.pathSeparator);
  return parts[parts.length - 1];
}

File formFile(Directory parent, String name) {
  return File("${parent.path}$separatorChar$name");
}

String readFile(Directory parent, String name) {
  var f = formFile(parent, name);
  if (!f.existsSync()) {
    fatalError("${f.path} does not exist.");
  }
  return f.readAsStringSync();
}

String checkHomeInPath(String path) {
  return path.replaceAll("~", getHomePath());
}