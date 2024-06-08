
import 'package:rl_tools/src/cli/processor.dart';
import 'package:rl_tools/src/shimmer/environment.dart';

abstract class ShimmerCommand {

  String get name;

  void execute(Environment environment, CommandLineProcessor cli);

  String usageText();
}