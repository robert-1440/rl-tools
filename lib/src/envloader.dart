import 'dart:io';

void processFile(String fileName, Map<String, String> environment) {
  var file = File(fileName);
  if (!file.existsSync()) {
    print("File $fileName does not exist.");
    return;
  }
  var lines = file.readAsLinesSync();
  int lineNumber = 0;
  for (var line in lines) {
    lineNumber += 1;
    line = line.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith("#")) {
      continue;
    }
    int index = line.indexOf("?=");
    bool conditional;
    int offset;
    if (index < 1) {
      index = line.indexOf("=");
      if (index < 1) {
        stderr.writeln("$fileName line $lineNumber: Invalid syntax - $line");
        continue;
      }
      conditional = false;
      offset = 1;
    } else {
      conditional = true;
      offset = 2;
    }
    var key = line.substring(0, index).trim();
    var value = line.substring(index + offset).trim();

    if (conditional) {
      if (Platform.environment.containsKey(key) || environment.containsKey(key)) {
        continue;
      }
    }
    environment[key] = value;
  }
}
