import 'dart:io';

import 'package:archive/archive.dart';
import 'package:rl_tools/src/cli/processor.dart';
import 'package:rl_tools/src/cli/util.dart';

class _Entry {
  final String name;
  final int compressedSize;
  final int size;

  _Entry(this.name, this.compressedSize, this.size);

  @override
  bool operator ==(Object other) {
    if (other is _Entry) {
      return name == other.name && compressedSize == other.compressedSize && size == other.size;
    }
    return super == other;
  }

  @override
  int get hashCode => name.hashCode ^ compressedSize.hashCode ^ size.hashCode;

  @override
  String toString() {
    return "$name: compressed=$compressedSize, size=$size";
  }
}

File _getFile(String fileName) {
  var file = File(fileName);
  if (!file.existsSync()) {
    fatalError("$fileName does not exist.");
  }
  return file;
}

void main(List<String> args) {
  var cli = CommandLineProcessor(args, usage: "Usage: zipcmp file1 file2");
  var file1 = cli.next("file1");
  var file2 = cli.next("file2");
  cli.assertNoMore();

  File f1 = _getFile(file1);
  File f2 = _getFile(file2);

  var left = _readZip(f1);
  var right = _readZip(f2);
  _compare(left, right);
}

void _compare(Map<String, _Entry> left, Map<String, _Entry> right) {
  bool any = false;
  var rightCopy = Map<String, _Entry>.from(right);
  for (var mapEntry in left.entries) {
    var key = mapEntry.key;
    var leftEntry = mapEntry.value;
    var rightEntry = rightCopy.remove(key);
    if (rightEntry == null) {
      print("Only in left: $key");
      any = true;
      continue;
    }
    if (leftEntry != rightEntry) {
      print("Different: $key - $leftEntry vs $rightEntry");
      any = true;
    }
  }
  for (var key in rightCopy.keys) {
    print("Only in right: $key");
    any = true;
  }
  if (!any) {
    print("No differences found.");
  }
}

Map<String, _Entry> _readZip(File file) {
  var entries = <String, _Entry>{};
  var bytes = file.readAsBytesSync();
  var decoder = ZipDecoder().decodeBytes(bytes);
  for (var file in decoder) {
    var name = file.name;
    var compressedSize = file.content.length;
    var size = file.size;
    entries[name] = _Entry(name, compressedSize, size);
  }
  return entries;
}
