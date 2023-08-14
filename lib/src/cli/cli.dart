import 'dart:collection';
import 'dart:io';

import 'processor.dart';
import 'util.dart';

class Command {
  final String name;

  final String description;

  final dynamic usage;

  final void Function(CommandLineProcessor) invoker;

  late String _moduleName;

  Command(this.name, this.description, dynamic usage, this.invoker) : usage = usage ?? "";

  String _generateUsage() {
    String message = "Usage: ${getOurExecutableName()} $_moduleName $name";
    String usageText = usage is String ? usage : usage();
    if (usageText.isNotEmpty) {
      message += " $usageText";
    }
    return '$message\n';
  }


  void invoke(CommandLineProcessor cli) {
    cli.setUsage(_generateUsage);
    invoker(cli);
  }
}

abstract class Module {
  String name();

  String description();

  List<Command Function()> commandLoaders();

  String usage() {
    var commands = commandLoaders().map((e) => e());
    var lb = LayoutBuilder();
    for (var cmd in commands) {
      lb.add(cmd.name, cmd.description);
    }
    return "\nAvailable actions:\n${lb.toString(indentCount: 1)}";
  }

  Command? findCommand(String name) {
    String moduleName = this.name();
    for (var loader in commandLoaders()) {
      var cmd = loader();
      if (cmd.name == name) {
        cmd._moduleName = moduleName;
        return cmd;
      }
    }
    return null;
  }
}

abstract class App {
  String usage();

  List<Module> modules();

  void setup(CommandLineProcessor cli);

}

class CommandLineRunner {
  final CommandLineProcessor _cli;

  final App app;

  late Map<String, Module> _moduleMap;

  CommandLineRunner.$(this._cli, this.app) {
    _cli.setUsage(_generateUsage);
    var map = {for (var m in app.modules()) m.name(): m};
    _moduleMap = SplayTreeMap<String, Module>();
    _moduleMap.addAll(map);
  }

  String nextArg([String? argName]) => _cli.next(argName);

  void execute() {
    String name = _cli.next("command");
    var impl = _moduleMap[name];
    if (impl == null) {
      usage("Unrecognized command: $name");
      exit(2);
    }
    _cli.setUsage(impl.usage());
    String action = _cli.next("action");
    var command = impl.findCommand(action);
    if (command == null) {
      _cli.invokeUsage("Invalid command '$action' for $name.");
      return;
    }

    command.invoke(_cli);
  }

  String _generateUsage() {
    var lb = LayoutBuilder();
    for (var m in _moduleMap.values) {
      lb.add(m.name(), m.description());
    }
    var text = lb.toString(indentCount: 1);
    var output = "Usage: ${getOurExecutableName()} ${app.usage()}\n\nAvailable commands:\n$text";

    return output;
  }

  void usage([String? message]) {
    String output = _generateUsage();
    if (message != null) {
      output = "$message\n\n$output";
    }
    _cli.setUsage(output);
    _cli.invokeUsage();
  }

  void assertHasMore() => _cli.hasMore();

  dynamic setProperty(String key, dynamic value) => _cli.setProperty(key, value);
}

/// Used to create a runner.
///
/// [args] => command line arguments.
/// [types] => list of module types that contain commands.
/// [usage] => usage text
/// [exitMode] => set to false when testing.
CommandLineRunner createRunner(List<String> args, App app, {bool? exitMode}) {
  var cli = CommandLineProcessor(args, usage: app.usage(), exitMode: exitMode);
  return CommandLineRunner.$(cli, app);
}

void init(List<String> args, App app, {bool? exitMode}) {
  var runner = createRunner(args, app, exitMode: exitMode);
  app.setup(runner._cli);
  runner.execute();
}