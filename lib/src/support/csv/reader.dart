import 'package:csv/csv.dart';
import 'package:rl_tools/src/cli/util.dart';

typedef Row = List<String>;

class CsvReader {
  final Row _headerRow;

  final Map<String, int> _headers;

  final List<Row> _rows;

  int _index = 0;

  Row? _currentRow;

  CsvReader._(this._headerRow, this._headers, this._rows);

  bool get hasNext => _index < _rows.length;

  Row get next {
    if (!hasNext) {
      throw StateError("No more rows");
    }
    _currentRow = _rows[_index++];
    return _currentRow!;
  }

  Row get headers => _headerRow;

  String get(String header) {
    if (_currentRow == null) {
      throw StateError("No current row");
    }
    var index = _headers[header];
    if (index == null) {
      throw ArgumentError("No such header: $header");
    }
    if (index >= _currentRow!.length) {
      return "";
    }
    return _currentRow![index];
  }

  Row get currentRow {
    if (_currentRow == null) {
      throw StateError("No current row");
    }
    return _currentRow!;
  }

  Map<String, String> get currentRowMap {
    var map = <String, String>{};
    var cr = currentRow;
    for (var i = 0; i < cr.length; i++) {
      map[_headerRow[i]] = cr[i];
    }
    return map;
  }

  String operator [](String header) => get(header);

  bool isValidHeader(String header) {
    return _headers.containsKey(header);
  }
}

List<Row> _parse(String content) {
  CsvToListConverter converter = CsvToListConverter(eol: '\n');
  return converter.convert(content, shouldParseNumbers: false);
}

void _builderHeaderMap(Map<String, int> headers, Row row) {
  for (int i = 0; i < row.length; i++) {
    var name = row[i];
    if (headers.containsKey(name)) {
      throw StateError("Duplicate header: $name");
    }
    headers[name] = i;
  }
}

CsvReader parseFile(String fileName) {
  List<Row> rows = _parse(readFile(fileName));
  if (rows.isEmpty) {
    throw StateError("No rows found");
  }
  Row? headerRow = rows.first;
  Map<String, int> headers = {};
  _builderHeaderMap(headers, headerRow);
  if (headers.isEmpty) {
    throw StateError("No headers found");
  }
  return CsvReader._(headerRow, headers, rows.sublist(1));
}
