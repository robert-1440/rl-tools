import 'dart:io';

import 'package:rl_tools/src/envloader.dart';
import 'package:rl_tools/src/cli/exec.dart';
import 'package:rl_tools/src/cli/processor.dart';

void setWorkspaceEnv(String name) {
  var envFile = File(name);
  if (!envFile.existsSync()) {
    print("File $name does not exist.");
    exit(1);
  }
  var file = File(".env");
  file.writeAsStringSync(name);
  print("Workspace environment set to $name.");
  exit(0);
}

String? loadDefaultEnv() {
  var file = File(".env");
  if (!file.existsSync()) {
    return null;
  }
  return file.readAsStringSync().trim();
}

void main(List<String> args) async {
  var cli = CommandLineProcessor(args,
      usage: "$getOurExecutableName() [--env envfile | --set envfile] [--test] [...]\nUsed to run 'make' with environment settings..");
  if (cli.hasOptionalArg("--help")) {
    cli.invokeUsage();
    exit(1);
  }
  var setEnv = cli.findOptionalArgPlusOne('--set');
  if (setEnv != null) {
    cli.assertNoMore();
    setWorkspaceEnv(setEnv);
  }
  var anyEnvs = false;

  var testIt = cli.hasOptionalArg("--test");

  Map<String, String> environment = {};
  for (;;) {
    var env = cli.findOptionalArgPlusOne("--env");
    if (env == null) {
      break;
    }
    anyEnvs = true;
    processFile(env, environment);
  }
  if (!anyEnvs) {
    var defaultEnv = loadDefaultEnv();
    if (defaultEnv != null) {
      print("Loading default environment $defaultEnv.");
      processFile(defaultEnv, environment);
    }
  }
  if (testIt) {
    stdout.writeln();
    for (var entry in environment.entries) {
      print("${entry.key}=${entry.value}");
    }
    stdout.writeln();
    exit(0);
  }
  await executeOut("make", cli.remaining(), environment);
}
