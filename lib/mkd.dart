import 'dart:io';

import 'package:rl_tools/src/cli/processor.dart';

void main(List<String> args) {
  var cli = CommandLineProcessor(args, usage: "$getOurExecutableName()\nUsed to create a folder with today's date as the name.");
  if (cli.hasOptionalArg("--help")) {
    cli.invokeUsage();
    exit(1);
  }
  cli.assertNoMore();

  var now = DateTime.now();
  var year = now.year.toString().padLeft(4, "0");
  var month = now.month.toString().padLeft(2, "0");
  var day = now.day.toString().padLeft(2, "0");
  var name = "$year-$month-$day";
  var dir = Directory(name);
  if (!dir.existsSync()) {
    dir.createSync();
    print("Created $name.");
  }
}
