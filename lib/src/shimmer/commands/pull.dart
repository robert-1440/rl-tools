import 'package:rl_tools/src/cli/processor.dart';
import 'package:rl_tools/src/shimmer/commands/command.dart';
import 'package:rl_tools/src/shimmer/environment.dart';

class PullCommand extends ShimmerCommand {
  PullCommand() {}

  @override
  String usageText() {
    return "pull";
  }

  @override
  void execute(Environment environment, CommandLineProcessor cli) {
    cli.assertNoMore();
  }

  @override
  String get name => "pull";
}
