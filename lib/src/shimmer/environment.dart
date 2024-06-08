import 'dart:io';

import 'package:rl_tools/src/cli/util.dart';

final homeDir = formHomeFile(".shimmer");
final envFile = formHomeFile("${homeDir.path}/env");

class Environment {
  final String name;

  late final File repoDir;

  Environment(this.name) {

  }
}
