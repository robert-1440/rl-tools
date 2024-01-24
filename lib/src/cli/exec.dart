import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ExecutionError implements Exception {
  final String message;

  final int exitCode;

  ExecutionError(this.message, this.exitCode);

  @override
  String toString() {
    return message;
  }
}

class Execution {
  final String stdoutString;

  final String stderrString;

  final int exitCode;

  Execution(this.stdoutString, this.stderrString, this.exitCode);
}

Future<Execution> execute(String command, List<String> args) async {
  var process = await Process.start(command, args);
  var stdoutBuilder = StringBuffer();
  var stream1 = process.stdout.transform(utf8.decoder).forEach(stdoutBuilder.writeln);
  var stderrBuilder = StringBuffer();
  var stream2 = process.stderr.transform(utf8.decoder).forEach(stderrBuilder.writeln);
  var exitCode = await process.exitCode;
  await stream1;
  await stream2;

  var execution = Execution(stdoutBuilder.toString(), stderrBuilder.toString(), exitCode);

  if (exitCode != 0) {
    throw ExecutionError(execution.stderrString, exitCode);
  }
  return execution;
}

Future<void> executeOut(String command, List<String> args, Map<String, String> environment) async {
  var process = await Process.start(command, args, environment: environment, includeParentEnvironment: true);
  // Completer<int> stdoutCompleter = Completer<int>();
  //
  // Completer<int> stderrCompleter = Completer<int>();
  //
  //
  // stdin.listen((List<int> data) {
  //   process.stdin.add(data);
  // }, onDone: () {
  //   process.stdin.close();
  // });
  //
  // process.stdout.transform(utf8.decoder).listen((String data) {
  //   print(data);
  // }, onDone: () {
  //   stdoutCompleter.complete(process.exitCode);
  // });
  //
  // process.stderr.transform(utf8.decoder).listen((String data) {
  //   stderr.write(data);
  // }, onDone: () {
  //   stderrCompleter.complete(process.exitCode);
  // });
  //
  // await Future.wait([stdoutCompleter.future, stderrCompleter.future]);

  stdout.addStream(process.stdout);
  stderr.addStream(process.stderr);
  process.stdin.addStream(stdin);

  var exitCode = await process.exitCode;
  exit(exitCode);
}
