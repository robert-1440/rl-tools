

import 'package:rl_tools/src/cli/processor.dart';
import 'package:rl_tools/src/support/csv/builder.dart';
import 'package:rl_tools/src/support/csv/reader.dart';

abstract class Filter {
  final String header;

  Filter(this.header);


  bool matches(CsvReader reader);
}

class _EqualsFilter extends Filter {

  final String _value;

  _EqualsFilter(super.header, this._value);

  @override
  bool matches(CsvReader reader) {
    return reader[header] == _value;
  }
}

void processFilter(String fileName, CsvReader reader, Filter filter) {
  var builder = createStdoutBuilder(reader.headers);
  while (reader.hasNext) {
    reader.next;
    if (filter.matches(reader)) {
      builder.addMapRow(reader.currentRowMap);
    }
  }
  builder.flush();
}

Filter _parseFilter(String expression) {
  var parts = expression.split("=");
  if (parts.length != 2) {
    throw ArgumentError("Invalid filter expression: $expression");
  }
  return _EqualsFilter(parts[0].trim(), parts[1].trimRight());
}

void main(List<String> args) {
  var cli = CommandLineProcessor(args, usage: "Usage: ${getOurExecutableName()} filter file filter-expression");
  var command = cli.next("command");
  if (command != "filter") {
    cli.invokeUsage("Unknown command: $command");
  }
  var file = cli.next("file");
  var expression = cli.next("filter-expression");
  cli.assertNoMore();
  var reader = parseFile(file);
  var filter = _parseFilter(expression);
  if (!reader.isValidHeader(filter.header)) {
    cli.invokeUsage("Invalid header: ${filter.header}");
  }
  processFilter(file, reader, filter);
}