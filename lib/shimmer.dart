

import 'package:rl_tools/src/cli/processor.dart';

void main(List<String> args) async {
  var cli = CommandLineProcessor(args, usage: "Usage: ${getOurExecutableName()} env command [args]");
  var env = cli.next("env");
  var command = cli.next("command");
  var otherArgs = cli.remaining();


}