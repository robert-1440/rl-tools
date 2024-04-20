import 'dart:io';

typedef DataWriter = void Function(String);

Map<String, int> _buildHeaderMap(List<String> headers) {
  Map<String, int> map = {};
  for (int i = 0; i < headers.length; i++) {
    var name = headers[i];
    if (map.containsKey(name)) {
      throw StateError("Duplicate header: $name");
    }
    map[name] = i;
  }
  return map;
}

List<dynamic> _initList(int size, List<dynamic>? inValues) {
  if (inValues != null && inValues.length == size) {
    return List.of(inValues);
  }
  List<dynamic> list = [];
  for (int i = 0; i < size; i++) {
    list.add(null);
  }
  if (inValues != null) {
    for (int i = 0; i < inValues.length; i++) {
      list[i] = inValues[i];
    }
  }
  return list;
}

String _toCellValue(dynamic obj) {
  if (obj == null) {
    return "";
  }
  if (obj is String) {
    return '"${obj.replaceAll('"', '""')}"';
  }
  return obj.toString();
}

class Row {
  final Map<String, int> _headerMap;

  final List<dynamic> _values;

  Row._$(this._headerMap, {List<dynamic>? inValues}) : _values = _initList(_headerMap.length, inValues);

  Row set(String header, dynamic value) {
    var index = _headerMap[header];
    if (index == null) {
      throw ArgumentError("No such header: $header");
    }
    _values[_headerMap[header]!] = value;
    return this;
  }

  operator []=(String header, dynamic value) {
    set(header, value);
  }

  List<String> _transform() => _values.map(_toCellValue).toList();

  String join(String delimiter) {
    return _transform().join(delimiter);
  }
}

void _defaultWriter(String str) {
  print(str);
}

class CsvBuilder {
  final List<String> _headers;

  final Map<String, int> _headerMap;

  final DataWriter _writer;

  final List<Row> _rows = [];

  final String _delimiter;

  int _rowCount = 0;

  CsvBuilder._$(this._headers, {String delimiter = ",", DataWriter? writer})
      : _headerMap = _buildHeaderMap(_headers),
        _delimiter = delimiter,
        _writer = writer ?? _defaultWriter;

  int get rowCount => _rowCount;

  void addMapRow(Map<String, dynamic> rowEntry) {
    var row = addRow();
    for (var entry in rowEntry.entries) {
      row[entry.key] = entry.value;
    }
  }

  Row addRow() {
    return _add(Row._$(_headerMap));
  }

  Row _add(Row row) {
    if (_rows.length >= 1000) {
      flush();
    }
    if (_rowCount == 0) {
      _rows.add(Row._$(_headerMap, inValues: _headers));
    }
    _rows.add(row);
    _rowCount++;
    return row;
  }

  void flush() {
    if (_rows.isNotEmpty) {
      for (var r in _rows) {
        _writer(r.join(_delimiter));
      }
      _rows.clear();
    }
  }
}

class _Sink {
  final File file;

  IOSink? sink;

  _Sink(this.file);

  IOSink _open() {
    if (!file.parent.existsSync()) {
      file.parent.create(recursive: true);
    }
    return file.openWrite();
  }

  void write(String data) {
    sink ??= _open();
    sink!.writeln(data);
  }

  Future<void> close() async {
    if (sink != null) {
      await sink!.flush();
      await sink!.close();
    }
  }
}

class CsvFileBuilder extends CsvBuilder {
  final _Sink _sink;

  CsvFileBuilder._$(_Sink sink, List<String> headers, {String delimiter = ","})
      : _sink = sink,
        super._$(headers, delimiter: delimiter, writer: sink.write);

  Future<void> close() async {
    flush();
    await _sink.close();
  }
}

CsvBuilder createStdoutBuilder(List<String> headers, {String delimiter = ","}) {
  return CsvBuilder._$(headers, delimiter: delimiter);
}

CsvBuilder createBuilder(List<String> headers, DataWriter writer, {String delimiter = ","}) {
  return CsvBuilder._$(headers, writer: writer, delimiter: delimiter);
}

CsvFileBuilder createFileBuilder(String fileName, List<String> headers, {String delimiter = ","}) {
  return CsvFileBuilder._$(_Sink(File(fileName)), headers, delimiter: delimiter);
}