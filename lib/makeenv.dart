import 'dart:io';

import 'package:rl_tools/src/cli/exec.dart';
import 'package:rl_tools/src/cli/processor.dart';

void processFile(String fileName, Map<String, String> environment) {
  var file = File(fileName);
  if (!file.existsSync()) {
    print("File $fileName does not exist.");
    return;
  }
  var lines = file.readAsLinesSync();
  for (var line in lines) {
    line = line.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith("#")) {
      continue;
    }
    int index = line.indexOf("=");
    if (index < 0) {
      print("Invalid line: $line");
      continue;
    }
    var key = line.substring(0, index).trim();
    var value = line.substring(index + 1).trim();
    environment[key] = value;
  }
}

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
      usage: "$getOurExecutableName() [--env envfile | --set envfile] [...]\nUsed to run 'make' with environment settings..");
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
  await executeOut("make", cli.remaining(), environment);
}
