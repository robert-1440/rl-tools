import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:rl_tools/src/cli/util.dart';
import 'package:yaml/yaml.dart';

class Project {
  final String path;
  final List<String> allowlist;

  Project(this.path, this.allowlist);

  factory Project.fromMap(dynamic map) {
    final allowlist = map['allowlist'];
    return Project(
      map['path'] as String,
      allowlist != null ? List<String>.from(allowlist) : <String>[],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'allowlist': allowlist,
    };
  }
}

class GitStatus {
  final String path;
  final String status;
  final bool isStaged;
  final bool isModified;
  final bool isUntracked;

  GitStatus(this.path, this.status, this.isStaged, this.isModified, this.isUntracked);
}

class GittyConfig {
  final List<Project> projects;

  GittyConfig(this.projects);

  factory GittyConfig.fromYaml(String yamlContent) {
    final doc = loadYaml(yamlContent);
    if (doc == null || doc['projects'] == null) {
      return GittyConfig([]);
    }
    final projectsList = doc['projects'] as List;
    final projects = projectsList.map((p) => Project.fromMap(p)).toList();
    return GittyConfig(projects);
  }

  String toYaml() {
    final data = {
      'projects': projects.map((p) => p.toMap()).toList(),
    };
    return _mapToYamlString(data);
  }

  Project? findProjectByPath(String path) {
    for (var project in projects) {
      var expandedPath = project.path.replaceFirst('~', Platform.environment['HOME'] ?? '');
      if (path == expandedPath) {
        return project;
      }
    }
    return null;
  }

  void addProject(Project project) {
    projects.add(project);
  }

  void removeProject(String path) {
    projects.removeWhere((p) => p.path == path);
  }

  String _mapToYamlString(Map<String, dynamic> map) {
    final buffer = StringBuffer();
    _writeMapToBuffer(buffer, map, 0);
    return buffer.toString();
  }

  void _writeMapToBuffer(StringBuffer buffer, dynamic value, int indent) {
    final indentStr = '  ' * indent;

    if (value is Map) {
      for (var entry in value.entries) {
        buffer.writeln('$indentStr${entry.key}:');
        _writeMapToBuffer(buffer, entry.value, indent + 1);
      }
    } else if (value is List) {
      for (var item in value) {
        buffer.write('$indentStr- ');
        if (item is Map) {
          buffer.writeln();
          _writeMapToBuffer(buffer, item, indent + 1);
        } else {
          buffer.writeln(item);
        }
      }
    } else {
      buffer.writeln('$indentStr$value');
    }
  }
}

GittyConfig _loadConfig() {
  final configPath = '${getHomePath()}/.gitty/profiles.yaml';
  final configFile = File(configPath);

  if (!configFile.existsSync()) {
    configFile.parent.createSync(recursive: true);
    final emptyConfig = GittyConfig([]);
    _saveConfig(emptyConfig);
    return emptyConfig;
  }

  return GittyConfig.fromYaml(configFile.readAsStringSync());
}

void _saveConfig(GittyConfig config) {
  final configPath = '${Platform.environment['HOME']}/.gitty/profiles.yaml';
  final configFile = File(configPath);
  configFile.writeAsStringSync(config.toYaml());
}

void _showAddProjectUsage(String currentDir) {
  final projectPath = currentDir.replaceFirst(getHomePath(), '~');
  print("\x1b[31mError: Current directory is not a tracked project\x1b[0m");
  print("To add this directory as a project, run:");
  print("  \x1b[32mgitty projects add\x1b[0m");
  print("(This will add project: $projectPath)");
}

List<GitStatus> _getGitStatus() {
  final result = Process.runSync('git', ['status', '--porcelain']);
  if (result.exitCode != 0) {
    print("\x1b[31mError: Not a git repository or git command failed\x1b[0m");
    exit(1);
  }

  final lines = result.stdout.toString().split('\n');
  final statuses = <GitStatus>[];

  for (var line in lines) {
    if (line.trim().isEmpty) continue;

    final statusChars = line.substring(0, 2);
    final filePath = line.substring(3);

    final isStaged = statusChars[0] != ' ' && statusChars[0] != '?';
    final isModified = statusChars[1] != ' ';
    final isUntracked = statusChars == '??';

    statuses.add(GitStatus(filePath, statusChars, isStaged, isModified, isUntracked));
  }

  return statuses;
}

void _analyzeAndReport(List<GitStatus> gitStatus, Project project, bool apply, GittyConfig config) {
  final allowedFiles = Set<String>.from(project.allowlist);
  final toStage = <String>[];
  final toUnstage = <String>[];
  final properlyStaged = <String>[];
  final unknownFiles = <String>[];
  final unknownUntracked = <String>[];

  for (var status in gitStatus) {
    final isAllowed = allowedFiles.contains(status.path);

    if (isAllowed) {
      // For allowed files
      if (status.isStaged && !status.isModified) {
        // File is staged and has no additional changes - properly staged
        properlyStaged.add(status.path);
      } else if (status.isModified) {
        // File has unstaged changes (may or may not also be staged)
        toStage.add(status.path);
      } else if (status.isUntracked) {
        // Untracked file that's in allowlist should be staged
        toStage.add(status.path);
      }
    } else {
      // For files NOT in allowlist
      if (status.isStaged) {
        // Unknown file that's staged should be unstaged
        toUnstage.add(status.path);
      } else if (status.isModified || status.isUntracked) {
        // Unknown file with changes or untracked
        if (status.isUntracked) {
          unknownUntracked.add(status.path);
        } else {
          unknownFiles.add(status.path);
        }
      }
    }
  }

  // Report results
  if (properlyStaged.isNotEmpty) {
    print("\x1b[32mProperly staged files:\x1b[0m");
    for (var file in properlyStaged) {
      print("  \x1b[32m✓ $file\x1b[0m");
    }
    print("");
  }

  if (toStage.isNotEmpty) {
    print("\x1b[31mFiles that need staging:\x1b[0m");
    for (var file in toStage) {
      print("  \x1b[31m+ $file\x1b[0m");
    }
    print("");

    if (apply) {
      for (var file in toStage) {
        Process.runSync('git', ['add', file]);
      }
      print("\x1b[32mStaged ${toStage.length} files\x1b[0m");
    }
  }

  if (toUnstage.isNotEmpty) {
    print("\x1b[31mUnknown files that are staged (should be unstaged):\x1b[0m");
    for (var file in toUnstage) {
      print("  \x1b[31m- $file\x1b[0m");
    }
    print("");

    if (apply) {
      for (var file in toUnstage) {
        Process.runSync('git', ['restore', '--staged', file]);
      }
      print("\x1b[32mUnstaged ${toUnstage.length} files\x1b[0m");
    }
  }

  // Show unknown files that have changes but aren't in allowlist
  if (unknownFiles.isNotEmpty) {
    print("\x1b[33mUnknown modified files (not in allowlist):\x1b[0m");
    for (var file in unknownFiles) {
      print("  \x1b[33m? $file\x1b[0m");
    }
    print("");
  }

  // Show unknown untracked files
  if (unknownUntracked.isNotEmpty) {
    print("\x1b[33mUnknown untracked files (not in allowlist):\x1b[0m");
    for (var file in unknownUntracked) {
      print("  \x1b[33m? $file\x1b[0m");
    }
    print("");
  }
}

void _stageCommand(bool apply, List<String> args) {
  final currentDir = Directory.current.path;
  final config = _loadConfig();
  final project = config.findProjectByPath(currentDir);

  if (project == null) {
    _showAddProjectUsage(currentDir);
    exit(1);
  }

  final gitStatus = _getGitStatus();
  _analyzeAndReport(gitStatus, project, apply, config);
}

void _addCommand(List<String> args) {
  if (args.isEmpty) {
    print("\x1b[31mError: Please specify one or more files to add\x1b[0m");
    print("Usage: gitty add <file1> [file2] [file3] ...");
    exit(1);
  }

  final currentDir = Directory.current.path;
  final config = _loadConfig();
  final project = config.findProjectByPath(currentDir);

  if (project == null) {
    print("\x1b[31mError: Current directory is not a tracked project\x1b[0m");
    exit(1);
  }

  final added = <String>[];
  final skipped = <String>[];

  for (final file in args) {
    if (!project.allowlist.contains(file)) {
      project.allowlist.add(file);
      added.add(file);
    } else {
      skipped.add(file);
    }
  }

  if (added.isNotEmpty) {
    _saveConfig(config);
    if (added.length == 1) {
      print("\x1b[32mAdded ${added[0]} to allowlist for project ${project.path}\x1b[0m");
    } else {
      print("\x1b[32mAdded ${added.length} files to allowlist for project ${project.path}:\x1b[0m");
      for (final file in added) {
        print("  \x1b[32m+ $file\x1b[0m");
      }
    }
  }

  if (skipped.isNotEmpty) {
    if (skipped.length == 1) {
      print("File ${skipped[0]} is already in the allowlist");
    } else {
      print("${skipped.length} files were already in the allowlist:");
      for (final file in skipped) {
        print("  \x1b[33m✓ $file\x1b[0m");
      }
    }
  }
}

void _rmCommand(List<String> args) {
  if (args.isEmpty) {
    print("\x1b[31mError: Please specify one or more files to remove\x1b[0m");
    print("Usage: gitty rm <file1> [file2] [file3] ...");
    exit(1);
  }

  final currentDir = Directory.current.path;
  final config = _loadConfig();
  final project = config.findProjectByPath(currentDir);

  if (project == null) {
    print("\x1b[31mError: Current directory is not a tracked project\x1b[0m");
    exit(1);
  }

  final removed = <String>[];
  final notFound = <String>[];

  for (final file in args) {
    if (project.allowlist.remove(file)) {
      removed.add(file);
    } else {
      notFound.add(file);
    }
  }

  if (removed.isNotEmpty) {
    _saveConfig(config);
    if (removed.length == 1) {
      print("\x1b[32mRemoved ${removed[0]} from allowlist for project ${project.path}\x1b[0m");
    } else {
      print("\x1b[32mRemoved ${removed.length} files from allowlist for project ${project.path}:\x1b[0m");
      for (final file in removed) {
        print("  \x1b[32m- $file\x1b[0m");
      }
    }
  }

  if (notFound.isNotEmpty) {
    if (notFound.length == 1) {
      print("File ${notFound[0]} was not in the allowlist");
    } else {
      print("${notFound.length} files were not in the allowlist:");
      for (final file in notFound) {
        print("  \x1b[33m? $file\x1b[0m");
      }
    }
  }
}

// Options that can be used with 'git commit' that we want to ignore when parsing the commit message
final List<String> _commitOptions = ['-am', '-m'];

void _removeOptions(List<String> args) {
  for (var option in _commitOptions) {
    var index = args.indexOf(option);
    if (index > -1) {
      args.removeAt(index);
    }
  }
}

void _commitCommand(List<String> args) {
  _removeOptions(args);
  if (args.isEmpty) {
    print("\x1b[31mError: Please specify a commit message\x1b[0m");
    print("Usage: gitty commit <message>");
    exit(1);
  }

  final commitMessage = args.join(' ');
  final currentDir = Directory.current.path;
  final config = _loadConfig();
  final project = config.findProjectByPath(currentDir);

  if (project == null) {
    _showAddProjectUsage(currentDir);
    exit(1);
  }

  // Get git status to check for staged and unstaged changes
  final gitStatus = _getGitStatus();
  final allowedFiles = Set<String>.from(project.allowlist);

  bool hasStagedChanges = false;
  final unstagedTrackedFiles = <String>[];

  for (var status in gitStatus) {
    if (status.isStaged) {
      hasStagedChanges = true;
    }

    // Check for unstaged changes in tracked (allowed) files
    if (allowedFiles.contains(status.path) && status.isModified && !status.isUntracked) {
      unstagedTrackedFiles.add(status.path);
    }
  }

  if (!hasStagedChanges) {
    print("\x1b[31mError: No staged changes to commit\x1b[0m");
    print("Use 'gitty stage --apply' to stage allowed files first");
    exit(1);
  }

  if (unstagedTrackedFiles.isNotEmpty) {
    print("\x1b[31mError: There are unstaged changes in tracked files:\x1b[0m");
    for (var file in unstagedTrackedFiles) {
      print("  \x1b[31m• $file\x1b[0m");
    }
    print("Use 'gitty stage' to stage these changes first");
    exit(2);
  }

  // All checks passed, perform the commit
  final result = Process.runSync('git', ['commit', '-m', commitMessage]);
  if (result.exitCode != 0) {
    print("\x1b[31mError: Git commit failed\x1b[0m");
    print(result.stderr);
    exit(1);
  }

  print("\x1b[32mCommit successful!\x1b[0m");
  print(result.stdout);
}

void tagTodayCommand(List<String> args) {
  if (args.isNotEmpty) {
    print("\x1b[31mError: tag-today command does not take any arguments\x1b[0m");
    print("Usage: gitty tag-today");
    exit(1);
  }
  // Ensure the current branch is main
  String s = _executeGit(['branch', '--show-current']).trim();
  if (s != 'main') {
    print("\x1b[31mError: You must be on the 'main' branch to use tag-today\x1b[0m");
    exit(1);
  }

  final date = DateTime.now();
  final tagName = "v${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  print("Creating/updating tag '$tagName' to current commit...");
  _executeGit(['tag', '-f', tagName]);
  _executeGit(['push', '-f', 'origin', tagName]);
  print("\x1b[32mTag '$tagName' created/updated to current commit\x1b[0m");
}

void snapshotCommand(List<String> args) {
  if (args.isNotEmpty) {
    print("\x1b[31mError: snapshot command does not take any arguments\x1b[0m");
    print("Usage: gitty snapshot");
    exit(1);
  }

  final currentBranch = _executeGit(['branch', '--show-current']).trim();
  if (currentBranch.isEmpty) {
    print("\x1b[31mError: Not on any branch (detached HEAD)\x1b[0m");
    exit(1);
  }

  final currentSha = _executeGit(['rev-parse', 'HEAD']).trim();

  final date = DateTime.now();
  final datePart = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  final baseName = "snapshots/$datePart";
  var branchName = baseName;

  var suffix = 0;
  while (true) {
    final result = Process.runSync('git', ['rev-parse', '--verify', branchName]);
    if (result.exitCode != 0) {
      break;
    }
    final existingSha = result.stdout.toString().trim();
    if (existingSha == currentSha) {
      print("Snapshot branch '$branchName' already exists at the same commit");
      return;
    }
    suffix++;
    branchName = "${baseName}_$suffix";
  }

  _executeGit(['checkout', '-b', branchName]);
  _executeGit(['push', '-u', 'origin', branchName]);
  _executeGit(['checkout', currentBranch]);

  print("\x1b[32mSnapshot branch '$branchName' created and pushed to origin\x1b[0m");
}


void _moveTagCommand(List<String> args) {
  if (args.length != 1) {
    print("\x1b[31mError: Please specify the tag name to move\x1b[0m");
    print("Usage: gitty move-tag <tag-name>");
    exit(1);
  }

  final tagName = args[0];
  _executeGit(['tag', '-d', tagName]);
  _executeGit(['push', 'origin', ':refs/tags/$tagName']);
  _executeGit(['tag', tagName]);
  _executeGit(['push', 'origin', tagName]);

  print("\x1b[32mTag '$tagName' moved to current commit\x1b[0m");
}

String _executeGit(List<String> args) {
  final result = Process.runSync('git', args, stdoutEncoding: utf8);
  if (result.exitCode != 0) {
    print("\x1b[31mError: Git command failed\x1b[0m");
    print(result.stderr);
    exit(1);
  }
  return result.stdout.toString();
}

void _projectsCommand(List<String> args) {
  if (args.isEmpty) {
    print("Usage: gitty projects <action>");
    print("");
    print("Actions:");
    print("  add     Add current directory as a project");
    print("  list    List all configured projects");
    print("  get     Show allowlist for current project");
    print("  rm [-f] Remove current project from tracking");
    return;
  }

  final action = args[0];
  final config = _loadConfig();

  switch (action) {
    case 'add':
      _projectsAddCommand(config);
      break;
    case 'list':
      _projectsListCommand(config);
      break;
    case 'get':
      _projectsGetCommand(config);
      break;
    case 'rm':
      _projectsRmCommand(config, args.skip(1).toList());
      break;
    default:
      print("\x1b[31mError: Unknown projects action '$action'\x1b[0m");
      print("Use: add, list, get, or rm");
      exit(1);
  }
}

void _projectsAddCommand(GittyConfig config) {
  final currentDir = Directory.current.path;
  final existingProject = config.findProjectByPath(currentDir);

  if (existingProject != null) {
    print("Current directory is already tracked as project: ${existingProject.path}");
    return;
  }

  final projectPath = currentDir.replaceFirst(getHomePath(), '~');
  final project = Project(projectPath, []);
  config.addProject(project);
  _saveConfig(config);
  print("\x1b[32mProject added for path: $projectPath\x1b[0m");
}

void _projectsListCommand(GittyConfig config) {
  if (config.projects.isEmpty) {
    print("No projects configured");
    return;
  }

  print("Configured projects:");
  for (var project in config.projects) {
    print("  \x1b[32m${project.path}\x1b[0m");
    print("    Files: ${project.allowlist.length} allowed");
    print("");
  }
}

void _projectsGetCommand(GittyConfig config) {
  final currentDir = Directory.current.path;
  final project = config.findProjectByPath(currentDir);

  if (project == null) {
    print("\x1b[31mError: Current directory is not a tracked project\x1b[0m");
    print("Use 'gitty projects add' to add it");
    exit(1);
  }

  print("Project: \x1b[32m${project.path}\x1b[0m");
  print("Allowlist:");

  if (project.allowlist.isEmpty) {
    print("  \x1b[33m(no files in allowlist)\x1b[0m");
  } else {
    for (var file in project.allowlist) {
      print("  \x1b[32m✓ $file\x1b[0m");
    }
  }
}

void _projectsRmCommand(GittyConfig config, List<String> args) {
  final currentDir = Directory.current.path;
  final project = config.findProjectByPath(currentDir);

  if (project == null) {
    print("\x1b[31mError: Current directory is not a tracked project\x1b[0m");
    exit(1);
  }

  final forceRemoval = args.contains('-f');

  if (!forceRemoval) {
    final confirmed = promptYes("Remove project ${project.path} from tracking");
    if (!confirmed) {
      print("Project removal cancelled");
      return;
    }
  }

  config.removeProject(project.path);
  _saveConfig(config);
  print("\x1b[32mRemoved project ${project.path} from tracking\x1b[0m");
}

/// A reference to a pull request on a GitHub (or GitHub Enterprise) host.
class PrRef {
  final String host;
  final String owner;
  final String repo;
  final int number;

  PrRef(this.host, this.owner, this.repo, this.number);

  /// The value to pass to gh's `-R` flag: `[HOST/]OWNER/REPO`.
  String get ghRepo => host == 'github.com' ? '$owner/$repo' : '$host/$owner/$repo';

  String get url => 'https://$host/$owner/$repo/pull/$number';

  @override
  String toString() => '$ghRepo#$number';
}

final RegExp _prUrlPattern = RegExp(
  r'^(?:https?://)?(?:www\.)?([A-Za-z0-9.-]+\.[A-Za-z]{2,})/'
  r'([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)/pull/(\d+)(?:[/?#].*)?$',
);

final RegExp _shortPattern = RegExp(
  r'^([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)(?:#|/pull/)(\d+)$',
);

/// Parses a pull request reference. Accepts a full PR URL
/// (`https://github.com/owner/repo/pull/123`, with or without scheme and with
/// trailing path/query/fragment), or the short forms `owner/repo#123` and
/// `owner/repo/pull/123`. Returns null if the text is not recognized.
PrRef? parsePrRef(String text) {
  final input = text.trim();
  if (input.isEmpty) {
    return null;
  }

  var match = _prUrlPattern.firstMatch(input);
  if (match != null) {
    return PrRef(match.group(1)!, match.group(2)!, match.group(3)!, int.parse(match.group(4)!));
  }

  match = _shortPattern.firstMatch(input);
  if (match != null) {
    return PrRef('github.com', match.group(1)!, match.group(2)!, int.parse(match.group(3)!));
  }

  return null;
}

ProcessResult _runGh(List<String> args, {String? workingDirectory}) {
  try {
    return Process.runSync('gh', args, workingDirectory: workingDirectory, stdoutEncoding: utf8, stderrEncoding: utf8);
  } on ProcessException catch (e) {
    print("\x1b[31mError: Unable to run 'gh': ${e.message}\x1b[0m");
    print("The GitHub CLI is required. See https://cli.github.com/");
    exit(1);
  }
}

/// Runs gh, forwarding its output, and exits on failure. [onFailure] runs
/// before exiting, giving the caller a chance to clean up.
void _execGh(List<String> args, String failureMessage, {String? workingDirectory, void Function()? onFailure}) {
  final result = _runGh(args, workingDirectory: workingDirectory);
  final out = result.stdout.toString().trim();
  final err = result.stderr.toString().trim();
  if (out.isNotEmpty) {
    print(out);
  }
  if (result.exitCode != 0) {
    print("\x1b[31m$failureMessage\x1b[0m");
    if (err.isNotEmpty) {
      print(err);
    }
    onFailure?.call();
    exit(1);
  }
  if (err.isNotEmpty) {
    print(err);
  }
}

bool _isEmptyDir(Directory dir) => dir.listSync().isEmpty;

String _joinPath(List<String> parts) => parts.where((p) => p.isNotEmpty).join(separatorChar);

/// Creates [dir] and any missing parents, returning the directories that were
/// actually created, outermost first, so they can be removed again on failure.
List<Directory> _createDirTracked(Directory dir) {
  final created = <Directory>[];
  for (var d = dir; !d.existsSync(); d = d.parent) {
    created.insert(0, d);
    if (d.parent.path == d.path) break;
  }
  dir.createSync(recursive: true);
  return created;
}

/// Removes directories created by [_createDirTracked], innermost first, but
/// only while they are still empty.
void _removeIfEmpty(List<Directory> dirs) {
  for (final dir in dirs.reversed) {
    if (!dir.existsSync() || !_isEmptyDir(dir)) return;
    dir.deleteSync();
  }
}

Future<void> _clonePrCommand(List<String> args) async {
  final positional = <String>[];
  var launchClaude = false;
  String? baseDirOption;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '-h' || arg == '--help') {
      _printClonePrUsage();
      return;
    }
    if (arg == '--claude') {
      launchClaude = true;
      continue;
    }
    if (arg == '--dir') {
      if (i + 1 >= args.length || args[i + 1].isEmpty) {
        print("\x1b[31mError: --dir requires a directory\x1b[0m");
        _printClonePrUsage();
        exit(1);
      }
      baseDirOption = args[++i];
      continue;
    }
    if (arg.startsWith('--dir=')) {
      baseDirOption = arg.substring('--dir='.length);
      if (baseDirOption.isEmpty) {
        print("\x1b[31mError: --dir requires a directory\x1b[0m");
        _printClonePrUsage();
        exit(1);
      }
      continue;
    }
    if (arg.startsWith('-')) {
      print("\x1b[31mError: Unknown option '$arg'\x1b[0m");
      _printClonePrUsage();
      exit(1);
    }
    positional.add(arg);
  }

  if (positional.isEmpty) {
    print("\x1b[31mError: Please specify a pull request URL\x1b[0m");
    _printClonePrUsage();
    exit(1);
  }
  if (positional.length > 1) {
    print("\x1b[31mError: Too many arguments (use --dir to choose the base directory)\x1b[0m");
    _printClonePrUsage();
    exit(1);
  }

  final ref = parsePrRef(positional[0]);
  if (ref == null) {
    print("\x1b[31mError: '${positional[0]}' is not a recognized pull request reference\x1b[0m");
    print("Expected something like https://github.com/owner/repo/pull/123 or owner/repo#123");
    exit(1);
  }

  // Look up the PR first: it fails fast on a bad reference or missing auth,
  // and the author decides where the clone goes.
  final view = _runGh([
    'pr',
    'view',
    '${ref.number}',
    '-R',
    ref.ghRepo,
    '--json',
    'number,title,state,headRefName,baseRefName,isCrossRepository,author,url',
  ]);
  if (view.exitCode != 0) {
    print("\x1b[31mError: Unable to read pull request ${ref.url}\x1b[0m");
    final err = view.stderr.toString().trim();
    if (err.isNotEmpty) {
      print(err);
    }
    exit(1);
  }

  final pr = jsonDecode(view.stdout.toString()) as Map<String, dynamic>;
  final title = pr['title'] as String? ?? '';
  final state = pr['state'] as String? ?? '';
  final headRef = pr['headRefName'] as String? ?? '';
  final baseRef = pr['baseRefName'] as String? ?? '';
  final author = (pr['author'] as Map<String, dynamic>?)?['login'] as String? ?? '';

  print("Pull request \x1b[32m${ref.ghRepo}#${ref.number}\x1b[0m: $title");
  showMap({
    'Author': author,
    'State': state,
    'Branch': headRef,
    'Base': baseRef,
    'Fork': pr['isCrossRepository'] == true ? 'yes' : 'no',
  }, separator: ':');

  if (state != 'OPEN') {
    print("\x1b[33mNote: pull request is $state\x1b[0m");
  }

  // Lay the clone out as <base>/<owner>/PR-<number>/<repo>, where the base
  // defaults to ~/review-repos/<author>.
  if (baseDirOption == null && !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(author)) {
    print("\x1b[31mError: Unable to determine the pull request's author; use --dir to choose the base directory\x1b[0m");
    exit(1);
  }
  final baseDir = checkHomeInPath(baseDirOption ?? '~/review-repos/$author');
  final prDir = _joinPath([baseDir, ref.owner, 'PR-${ref.number}']);
  final targetDir = _joinPath([prDir, ref.repo]);

  if (File(targetDir).existsSync()) {
    print("\x1b[31mError: '$targetDir' already exists and is not a directory\x1b[0m");
    exit(1);
  }
  final dir = Directory(targetDir);
  if (dir.existsSync() && !_isEmptyDir(dir)) {
    print("\x1b[31mError: Directory '$targetDir' already exists and is not empty\x1b[0m");
    exit(1);
  }

  final created = _createDirTracked(Directory(prDir));
  void cleanup() => _removeIfEmpty(created);

  print("Cloning ${ref.ghRepo} into '$targetDir'...");
  _execGh(['repo', 'clone', ref.ghRepo, targetDir], 'Error: Clone failed', onFailure: cleanup);

  print("Checking out pull request ${ref.number}...");
  // 'gh pr checkout' creates the local branch and, for fork PRs, wires up the
  // remote/refspec needed to track it.
  _execGh(['pr', 'checkout', '${ref.number}'], 'Error: Checkout failed', workingDirectory: targetDir);

  final branch = Process.runSync('git', ['branch', '--show-current'],
          workingDirectory: targetDir, stdoutEncoding: utf8)
      .stdout
      .toString()
      .trim();

  print("\x1b[32mReady: $targetDir on branch '${branch.isEmpty ? headRef : branch}'\x1b[0m");

  if (launchClaude) {
    await _launchClaudeForPr(targetDir, ref.number);
  }
}

/// Runs `claude` in [dir] with a session ID chosen here, first writing a
/// `resume.sh` next to the repository that updates the checkout to the pull
/// request's latest commits and picks the session back up.
Future<void> _launchClaudeForPr(String dir, int prNumber) async {
  final sessionId = _randomUuid();
  final resumeScript = File(_joinPath([Directory(dir).parent.path, 'resume.sh']));
  resumeScript.writeAsStringSync('#!/bin/sh\n'
      'cd ${_shellQuote(Directory(dir).absolute.path)} || exit 1\n'
      'gh pr checkout $prNumber --force || exit 1\n'
      'exec claude --resume $sessionId "\$@"\n');
  Process.runSync('chmod', ['+x', resumeScript.path]);
  print("Wrote '${resumeScript.path}' to resume this session");

  await _launchClaude(dir, ['--session-id', sessionId]);
}

/// Runs `claude` in [dir] attached to this terminal, then exits with claude's
/// exit code.
Future<void> _launchClaude(String dir, [List<String> args = const []]) async {
  print("Starting 'claude' in '$dir'...");
  final Process process;
  try {
    process = await Process.start('claude', args, workingDirectory: dir, mode: ProcessStartMode.inheritStdio);
  } on ProcessException catch (e) {
    print("\x1b[31mError: Unable to start claude: ${e.message}\x1b[0m");
    exit(1);
  }
  // Ctrl-C is claude's to handle; don't let it kill gitty out from under it.
  ProcessSignal.sigint.watch().listen((_) {});
  exit(await process.exitCode);
}

/// A random (version 4) UUID.
String _randomUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Quotes [value] for use as a single word in a POSIX shell script.
String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

void _printClonePrUsage() {
  print("Usage: gitty clone-pr [--dir <dir>] [--claude] <pr-url>");
  print("");
  print("Clones the pull request's repository and checks out its branch using gh,");
  print("laid out as:");
  print("");
  print("  <base-dir>/<owner>/PR-<number>/<repo>");
  print("");
  print("Accepted references:");
  print("  https://github.com/owner/repo/pull/123");
  print("  github.com/owner/repo/pull/123");
  print("  owner/repo#123");
  print("");
  print("The base directory defaults to ~/review-repos/<author>, where <author> is");
  print("the pull request author's GitHub login.");
  print("");
  print("Options:");
  print("  --dir <dir> Use <dir> as the base directory instead.");
  print("  --claude    After checkout, run 'claude' in the cloned repository;");
  print("              gitty exits when claude does. Also writes an executable");
  print("              <base-dir>/<owner>/PR-<number>/resume.sh that updates the");
  print("              checkout to the PR's latest commits and resumes that");
  print("              claude session.");
}

/// The repository a git remote URL points at.
class RemoteRepo {
  final String host;

  /// The organization or user; for hosts with nested groups, the full group
  /// path (`group/subgroup`).
  final String owner;
  final String repo;

  RemoteRepo(this.host, this.owner, this.repo);

  @override
  String toString() => '$host/$owner/$repo';
}

final RegExp _scpRemotePattern = RegExp(r'^(?:[^@/]+@)?([^:/]+):(?!//)(.+)$');
final RegExp _urlRemotePattern = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*://(?:[^@/]+@)?([^/:]+)(?::\d+)?/(.+)$');

/// Parses a git remote URL: `https://host/owner/repo.git`,
/// `ssh://git@host[:port]/owner/repo.git`, or the scp-like
/// `git@host:owner/repo.git`. Returns null if it has no owner/repo path.
RemoteRepo? parseRemoteUrl(String url) {
  final input = url.trim();
  final match = _urlRemotePattern.firstMatch(input) ?? _scpRemotePattern.firstMatch(input);
  if (match == null) {
    return null;
  }

  var path = match.group(2)!;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path.endsWith('.git')) {
    path = path.substring(0, path.length - 4);
  }
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.length < 2 || parts.any((p) => p == '.' || p == '..')) {
    return null;
  }
  return RemoteRepo(match.group(1)!, parts.sublist(0, parts.length - 1).join('/'), parts.last);
}

/// Runs git in the current directory, returning its trimmed stdout, or null
/// if it fails.
String? _gitOutput(List<String> args) {
  final result = Process.runSync('git', args, stdoutEncoding: utf8, stderrEncoding: utf8);
  return result.exitCode == 0 ? result.stdout.toString().trim() : null;
}

Never _fail(String message) {
  print("\x1b[31mError: $message\x1b[0m");
  exit(1);
}

Future<void> _cloneBranchCommand(List<String> args) async {
  var launchClaude = false;
  var replaceExisting = false;
  for (final arg in args) {
    if (arg == '-h' || arg == '--help') {
      _printCloneBranchUsage();
      return;
    }
    if (arg == '--claude') {
      launchClaude = true;
      continue;
    }
    if (arg == '-d') {
      replaceExisting = true;
      continue;
    }
    print("\x1b[31mError: Unknown ${arg.startsWith('-') ? 'option' : 'argument'} '$arg'\x1b[0m");
    _printCloneBranchUsage();
    exit(1);
  }

  if (_gitOutput(['rev-parse', '--show-toplevel']) == null) {
    _fail("Not inside a git repository");
  }

  final branch = _gitOutput(['branch', '--show-current']) ?? '';
  if (branch.isEmpty) {
    _fail("HEAD is detached; check out the branch to clone first");
  }
  if (_gitOutput(['rev-parse', '--verify', '--quiet', 'HEAD^{commit}']) == null) {
    _fail("Branch '$branch' has no commits");
  }

  // The branch's upstream says both which repository to clone and which
  // branch there to check out (it need not share the local branch's name).
  final remote = _gitOutput(['config', '--get', 'branch.$branch.remote']);
  final mergeRef = _gitOutput(['config', '--get', 'branch.$branch.merge']);
  if (remote == null || mergeRef == null) {
    _fail("Branch '$branch' has not been pushed (it has no upstream branch)");
  }
  if (remote == '.') {
    _fail("Branch '$branch' tracks a local branch, so there is no repository to clone");
  }
  final remoteBranch = mergeRef.replaceFirst(RegExp(r'^refs/heads/'), '');

  // The URL as configured, before any insteadOf rewriting; git clone applies
  // that itself.
  final remoteUrl = _gitOutput(['config', '--get', 'remote.$remote.url']);
  if (remoteUrl == null) {
    _fail("Unable to find the URL of remote '$remote'");
  }
  final repo = parseRemoteUrl(remoteUrl);
  if (repo == null) {
    _fail("Unable to determine the repository from remote '$remote' ($remoteUrl)");
  }

  final upstream = '$remote/$remoteBranch';
  if (_gitOutput(['rev-parse', '--verify', '--quiet', '@{upstream}^{commit}']) == null) {
    _fail("Upstream branch '$upstream' no longer exists; push '$branch' first");
  }
  final unpushed = int.parse(_gitOutput(['rev-list', '--count', '@{upstream}..HEAD']) ?? '0');
  if (unpushed > 0) {
    _fail("Branch '$branch' has $unpushed commit${unpushed == 1 ? '' : 's'} not pushed to '$upstream'");
  }

  // A branch with nothing beyond the default branch has nothing to review.
  final defaultBranch = _gitOutput(['symbolic-ref', '--quiet', '--short', 'refs/remotes/$remote/HEAD']);
  if (defaultBranch == upstream) {
    _fail("Branch '$branch' is the default branch of '$remote'; there is nothing to review");
  }
  if (defaultBranch != null && _gitOutput(['rev-list', '--count', '$defaultBranch..HEAD']) == '0') {
    _fail("Branch '$branch' has no commits that are not already on '$defaultBranch'");
  }

  if ((_gitOutput(['status', '--porcelain']) ?? '').isNotEmpty) {
    print("\x1b[33mNote: uncommitted changes in this working tree will not be in the clone\x1b[0m");
  }

  // Like clone-pr's <owner>/PR-<number>/<repo>. A branch name with slashes
  // nests; git itself keeps such names from colliding (no 'a' next to 'a/b').
  final branchDir = _joinPath([checkHomeInPath('~/review-repos/local'), repo.owner, remoteBranch]);
  final targetDir = _joinPath([branchDir, repo.repo]);
  if (File(targetDir).existsSync()) {
    _fail("'$targetDir' already exists and is not a directory");
  }
  final dir = Directory(targetDir);
  if (dir.existsSync() && !replaceExisting && !_isEmptyDir(dir)) {
    _fail("Directory '$targetDir' already exists and is not empty (use -d to replace it)");
  }

  print("Branch \x1b[32m$upstream\x1b[0m of $repo");
  if (dir.existsSync() && replaceExisting) {
    print("Deleting existing '$targetDir'...");
    dir.deleteSync(recursive: true);
  }
  final created = _createDirTracked(Directory(branchDir));

  print("Cloning $remoteUrl into '$targetDir'...");
  final clone = Process.runSync('git', ['clone', '--branch', remoteBranch, remoteUrl, targetDir],
      stdoutEncoding: utf8, stderrEncoding: utf8);
  if (clone.exitCode != 0) {
    print("\x1b[31mError: Clone failed\x1b[0m");
    final err = clone.stderr.toString().trim();
    if (err.isNotEmpty) {
      print(err);
    }
    _removeIfEmpty(created);
    exit(1);
  }

  print("\x1b[32mReady: $targetDir on branch '$remoteBranch'\x1b[0m");

  if (launchClaude) {
    await _launchClaude(targetDir);
  }
}

void _printCloneBranchUsage() {
  print("Usage: gitty clone-branch [-d] [--claude]");
  print("");
  print("Clones the repository the current branch is pushed to and checks out that");
  print("branch, laid out as:");
  print("");
  print("  ~/review-repos/local/<owner>/<branch>/<repo>");
  print("");
  print("Fails if the current branch has no commits of its own, has not been");
  print("pushed, or has commits that have not been pushed.");
  print("");
  print("Options:");
  print("  -d          Delete the target directory first if it already exists.");
  print("  --claude    After checkout, run 'claude' in the cloned repository;");
  print("              gitty exits when claude does.");
}

/// One cloned pull request found under ~/review-repos, and what GitHub says
/// about it now.
class _ReviewedPr {
  final Directory dir;
  final String folder;
  final int number;
  final String url;
  final String branch;
  final String author;
  final String status;

  /// True once the pull request is merged or closed.
  final bool finished;

  /// True while the pull request is waiting on the current user's review.
  final bool reviewRequested;

  _ReviewedPr(this.dir, this.folder, this.number, this.url, this.branch, this.author, this.status,
      {this.finished = false, this.reviewRequested = false});
}

final RegExp _prFolderPattern = RegExp(r'^PR-(\d+)$');

/// Finds the `PR-<number>` folders under [root]. It does not descend into
/// them, into git repositories, or into hidden folders.
List<Directory> _findPrFolders(Directory root) {
  final found = <Directory>[];
  void walk(Directory dir) {
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final entry in entries.whereType<Directory>()) {
      final name = getName(entry);
      if (name.startsWith('.')) continue;
      if (_prFolderPattern.hasMatch(name)) {
        found.add(entry);
      } else if (!Directory(_joinPath([entry.path, '.git'])).existsSync()) {
        walk(entry);
      }
    }
  }

  walk(root);
  return found;
}

/// Describes a pull request's state for the review table: MERGED, CLOSED, or
/// OPEN qualified by draft status or the review decision.
String _describePrStatus(Map<String, dynamic> pr) {
  final state = pr['state'] as String? ?? '';
  if (state != 'OPEN') return state;
  if (pr['isDraft'] == true) return 'OPEN (draft)';
  switch (pr['reviewDecision']) {
    case 'APPROVED':
      return 'OPEN (approved)';
    case 'CHANGES_REQUESTED':
      return 'OPEN (changes requested)';
    case 'REVIEW_REQUIRED':
      return 'OPEN (review required)';
  }
  return state;
}

/// True if [pr] (`gh pr view --json state,reviewRequests` output) is open and
/// has a pending review request for [login]. Requests made of a team are not
/// counted, as telling whether [login] is on the team takes more API access.
bool isReviewRequestedFrom(Map<String, dynamic> pr, String login) {
  if (pr['state'] != 'OPEN') return false;
  final requests = pr['reviewRequests'];
  if (requests is! List) return false;
  final me = login.toLowerCase();
  return requests.any((r) => r is Map && (r['login'] as String?)?.toLowerCase() == me);
}

/// The login of the user gh is authenticated as on [host], or null if gh
/// cannot tell.
Future<String?> _ghLogin(String host) async {
  try {
    final result = await Process.run(
        'gh', ['api', 'user', '-q', '.login', if (host != 'github.com') ...['--hostname', host]],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    final login = result.stdout.toString().trim();
    return result.exitCode == 0 && login.isNotEmpty ? login : null;
  } on ProcessException {
    return null;
  }
}

/// [loginFor] gives the current user's login on a host, for the Review column.
Future<_ReviewedPr> _checkPrFolder(
    Directory prDir, String displayFolder, Future<String?> Function(String host) loginFor) async {
  final number = int.parse(_prFolderPattern.firstMatch(getName(prDir))!.group(1)!);
  _ReviewedPr result(String status,
          {String url = '',
          String branch = '',
          String author = '',
          bool finished = false,
          bool reviewRequested = false}) =>
      _ReviewedPr(prDir, displayFolder, number, url, branch, author, status,
          finished: finished, reviewRequested: reviewRequested);

  final clones = prDir
      .listSync(followLinks: false)
      .whereType<Directory>()
      .where((d) => Directory(_joinPath([d.path, '.git'])).existsSync())
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (clones.isEmpty) {
    return result('error: no clone found');
  }

  final remote = await Process.run('git', ['config', '--get', 'remote.origin.url'],
      workingDirectory: clones.first.path, stdoutEncoding: utf8);
  final repo = remote.exitCode == 0 ? parseRemoteUrl(remote.stdout.toString()) : null;
  if (repo == null) {
    return result('error: no usable origin remote');
  }
  final ghRepo = repo.host == 'github.com' ? '${repo.owner}/${repo.repo}' : repo.toString();
  final fallbackUrl = 'https://$repo/pull/$number';

  final ProcessResult view;
  try {
    view = await Process.run(
        'gh', ['pr', 'view', '$number', '-R', ghRepo, '--json', 'url,headRefName,author,state,isDraft,reviewDecision,reviewRequests'],
        stdoutEncoding: utf8, stderrEncoding: utf8);
  } on ProcessException catch (e) {
    return result('error: unable to run gh: ${e.message}', url: fallbackUrl);
  }
  if (view.exitCode != 0) {
    final err = view.stderr.toString().trim().split('\n').first;
    return result('error: ${err.isEmpty ? 'gh pr view failed' : err}', url: fallbackUrl);
  }

  final pr = jsonDecode(view.stdout.toString()) as Map<String, dynamic>;
  final login = await loginFor(repo.host);
  return result(_describePrStatus(pr),
      url: pr['url'] as String? ?? fallbackUrl,
      branch: pr['headRefName'] as String? ?? '',
      author: (pr['author'] as Map<String, dynamic>?)?['login'] as String? ?? '',
      finished: pr['state'] == 'MERGED' || pr['state'] == 'CLOSED',
      reviewRequested: login != null && isReviewRequestedFrom(pr, login));
}

Future<void> _prReviewCheckCommand(List<String> args) async {
  var prune = false;
  var interactive = false;
  for (final arg in args) {
    if (arg == '-h' || arg == '--help') {
      _printPrReviewCheckUsage();
      return;
    }
    if (arg == '--prune') {
      prune = true;
      continue;
    }
    if (arg == '-i') {
      interactive = true;
      continue;
    }
    print("\x1b[31mError: Unknown ${arg.startsWith('-') ? 'option' : 'argument'} '$arg'\x1b[0m");
    _printPrReviewCheckUsage();
    exit(1);
  }
  if (prune && interactive) {
    _fail("--prune and -i cannot be used together");
  }

  final home = getHomePath();
  final root = Directory(_joinPath([home, 'review-repos']));
  if (!root.existsSync()) {
    _fail("'${root.path}' does not exist");
  }

  final folders = _findPrFolders(root)..sort((a, b) => a.path.compareTo(b.path));
  if (folders.isEmpty) {
    print("No PR-<number> folders found under '${root.path}'");
    return;
  }

  String display(String path) => path.startsWith('$home/') ? '~${path.substring(home.length)}' : path;

  // Ask GitHub about a few pull requests at a time.
  print("Checking ${folders.length} pull request${folders.length == 1 ? '' : 's'}...");
  const batchSize = 8;
  // One login lookup per host, shared by every pull request on it.
  final logins = <String, Future<String?>>{};
  Future<String?> loginFor(String host) => logins.putIfAbsent(host, () => _ghLogin(host));
  final results = <_ReviewedPr>[];
  for (var i = 0; i < folders.length; i += batchSize) {
    final batch = folders.skip(i).take(batchSize);
    results.addAll(await Future.wait(batch.map((d) => _checkPrFolder(d, display(d.path), loginFor))));
  }

  final table = TableBuilder()
    ..addColumn('url', displayName: 'URL')
    ..addColumn('branch', displayName: 'Branch')
    ..addColumn('author', displayName: 'Author')
    ..addColumn('status', displayName: 'Status')
    ..addColumn('review', displayName: 'Review')
    ..addColumn('folder', displayName: 'Folder');
  for (final pr in results) {
    table.addRow({
      'url': pr.url,
      'branch': pr.branch,
      'author': pr.author,
      'status': pr.status,
      'review': pr.reviewRequested ? 'requested' : '',
      'folder': pr.folder,
    });
  }
  if (interactive) {
    await _pickPrToResume(results, table.build());
    return;
  }
  print("\n${table.build()}");

  if (prune) {
    _prunePrFolders(results.where((pr) => pr.finished).toList(), root);
  }
}

/// Reads single keys from the controlling terminal. While open, the terminal
/// is unbuffered and silent, with a short read timeout so that a lone ESC can
/// be told apart from the start of an arrow key's escape sequence.
class _TerminalKeys {
  final RandomAccessFile _tty;
  final String _savedMode;

  _TerminalKeys._(this._tty, this._savedMode);

  /// Returns null when there is no terminal to read from.
  static _TerminalKeys? open() {
    final saved = _stty(['-g']);
    if (saved == null) return null;
    // -isig: Ctrl-C arrives as a key, so the terminal is always restored.
    if (_stty(['-icanon', '-echo', '-isig', 'min', '0', 'time', '1']) == null) return null;
    try {
      return _TerminalKeys._(File('/dev/tty').openSync(), saved);
    } on FileSystemException {
      _stty([saved]);
      return null;
    }
  }

  static String? _stty(List<String> args) {
    final result = Process.runSync('sh', ['-c', 'stty "\$@" < /dev/tty', 'stty', ...args], stdoutEncoding: utf8);
    return result.exitCode == 0 ? result.stdout.toString().trim() : null;
  }

  int _read() => _tty.readByteSync();

  /// Waits for a key: 'up', 'down', 'enter', 'open', 'copy-branch', 'escape',
  /// 'quit', or null for anything else.
  String? next() {
    var byte = _read();
    while (byte < 0) {
      byte = _read();
    }
    switch (byte) {
      case 13:
      case 10:
        return 'enter';
      case 3:
      case 113: // q
        return 'quit';
      case 107: // k
        return 'up';
      case 106: // j
        return 'down';
      case 111: // o
      case 79: // O
        return 'open';
      case 98: // b
      case 66: // B
        return 'copy-branch';
      case 27:
        final second = _read();
        if (second < 0) return 'escape';
        if (second != 91 && second != 79) return null; // '[' or 'O'
        final third = _read();
        if (third == 65) return 'up';
        if (third == 66) return 'down';
        // Swallow the rest of a longer sequence, such as a function key.
        while (_read() >= 0) {}
        return null;
    }
    return null;
  }

  void close() {
    _tty.closeSync();
    _stty([_savedMode]);
  }
}

/// Shows [tableText] with one highlighted row that the arrow keys move. Enter
/// runs that pull request's resume.sh, o opens it in the browser, b copies its
/// branch name, and ESC (or q) exits.
Future<void> _pickPrToResume(List<_ReviewedPr> prs, String tableText) async {
  final lines = tableText.split('\n').where((l) => l.isNotEmpty).toList();
  final header = lines.take(2).toList();
  final rows = lines.skip(2).toList();

  final keys = _TerminalKeys.open();
  if (keys == null) {
    _fail("-i needs a terminal");
  }

  final screenLines = stdout.hasTerminal ? stdout.terminalLines : 24;
  final visible = max(1, min(rows.length, screenLines - header.length - 3));
  var selected = 0;
  var top = 0;
  var message = '';
  var drawn = 0;

  void draw() {
    if (selected < top) top = selected;
    if (selected >= top + visible) top = selected - visible + 1;
    final out = StringBuffer();
    if (drawn > 0) out.write('\x1b[${drawn}A');
    for (final line in header) {
      out.write('\r\x1b[2K$line\n');
    }
    for (var i = top; i < top + visible; i++) {
      out.write(i == selected ? '\r\x1b[2K\x1b[7m${rows[i]}\x1b[0m\n' : '\r\x1b[2K${rows[i]}\n');
    }
    final more = rows.length > visible ? '  (${selected + 1}/${rows.length})' : '';
    out.write('\r\x1b[2K\x1b[2m↑/↓ select, Enter resume, o open in browser, b copy branch, Esc exit$more\x1b[0m\n');
    out.write('\r\x1b[2K$message\n');
    drawn = header.length + visible + 2;
    stdout.write(out);
  }

  stdout.write('\n\x1b[?25l');
  _ReviewedPr? chosen;
  try {
    for (;;) {
      draw();
      switch (keys.next()) {
        case 'up':
          selected = (selected - 1 + rows.length) % rows.length;
          message = '';
        case 'down':
          selected = (selected + 1) % rows.length;
          message = '';
        case 'escape':
        case 'quit':
          return;
        case 'enter':
          final pr = prs[selected];
          if (File(_joinPath([pr.dir.path, 'resume.sh'])).existsSync()) {
            chosen = pr;
            return;
          }
          message = '\x1b[33mNo resume.sh in ${pr.folder}\x1b[0m';
        case 'open':
          message = _openInBrowser(prs[selected].url);
        case 'copy-branch':
          message = await _copyToClipboard(prs[selected].branch, 'branch name');
      }
    }
  } finally {
    keys.close();
    stdout.write('\x1b[?25h');
    if (chosen != null) {
      await _runResumeScript(chosen);
    }
  }
}

/// Opens [url] in the default browser, returning a line describing the result.
String _openInBrowser(String url) {
  if (url.isEmpty) {
    return '\x1b[33mNo URL for this pull request\x1b[0m';
  }
  final opener = Platform.isMacOS ? 'open' : 'xdg-open';
  try {
    final result = Process.runSync(opener, [url]);
    if (result.exitCode == 0) {
      return 'Opened $url';
    }
  } on ProcessException {
    // Reported below.
  }
  return '\x1b[31mUnable to open $url with $opener\x1b[0m';
}

/// Copies [text] to the clipboard, returning a line describing the result.
/// [what] names the text in that line.
Future<String> _copyToClipboard(String text, String what) async {
  if (text.isEmpty) {
    return '\x1b[33mNo $what for this pull request\x1b[0m';
  }
  final candidates = Platform.isMacOS
      ? [
          ['pbcopy'],
        ]
      : [
          ['wl-copy'],
          ['xclip', '-selection', 'clipboard'],
          ['xsel', '--clipboard', '--input'],
        ];
  for (final command in candidates) {
    try {
      final process = await Process.start(command.first, command.sublist(1));
      process.stdin.write(text);
      await process.stdin.close();
      if (await process.exitCode == 0) {
        return 'Copied $what: $text';
      }
    } on ProcessException {
      // Not installed; try the next one.
    }
  }
  return '\x1b[31mUnable to copy to the clipboard (tried ${candidates.map((c) => c.first).join(', ')})\x1b[0m';
}

/// Runs [pr]'s resume.sh attached to this terminal, then exits with its exit
/// code.
Future<void> _runResumeScript(_ReviewedPr pr) async {
  final script = _joinPath([pr.dir.path, 'resume.sh']);
  print("Running ${pr.folder}/resume.sh...");
  final Process process;
  try {
    process = await Process.start(script, [], workingDirectory: pr.dir.path, mode: ProcessStartMode.inheritStdio);
  } on ProcessException catch (e) {
    _fail("Unable to run '$script': ${e.message}");
  }
  // Ctrl-C belongs to the script (and claude); don't let it kill gitty.
  ProcessSignal.sigint.watch().listen((_) {});
  exit(await process.exitCode);
}

/// Deletes the folders of merged and closed pull requests after confirmation,
/// keeping any whose clone has uncommitted changes, then removes parent
/// folders left empty below [root].
void _prunePrFolders(List<_ReviewedPr> finished, Directory root) {
  if (finished.isEmpty) {
    print("Nothing to prune: no merged or closed pull requests");
    return;
  }

  final toDelete = <_ReviewedPr>[];
  for (final pr in finished) {
    final dirty = pr.dir
        .listSync(followLinks: false)
        .whereType<Directory>()
        .where((d) => Directory(_joinPath([d.path, '.git'])).existsSync())
        .any((clone) {
      final status = Process.runSync('git', ['status', '--porcelain'], workingDirectory: clone.path, stdoutEncoding: utf8);
      return status.exitCode != 0 || status.stdout.toString().trim().isNotEmpty;
    });
    if (dirty) {
      print("\x1b[33mKeeping ${pr.folder}: its clone has uncommitted changes\x1b[0m");
    } else {
      toDelete.add(pr);
    }
  }
  if (toDelete.isEmpty) {
    return;
  }

  print("\nFolders of merged or closed pull requests:");
  for (final pr in toDelete) {
    print("  ${pr.folder}  (${pr.status})");
  }
  if (!promptYes(toDelete.length == 1 ? "Delete this folder" : "Delete these ${toDelete.length} folders")) {
    print("Nothing deleted");
    return;
  }

  final rootPath = root.absolute.path;
  for (final pr in toDelete) {
    pr.dir.deleteSync(recursive: true);
    for (var parent = pr.dir.parent;
        parent.absolute.path.startsWith('$rootPath/') && parent.existsSync() && _isEmptyDir(parent);
        parent = parent.parent) {
      parent.deleteSync();
    }
  }
  print("\x1b[32mDeleted ${toDelete.length} folder${toDelete.length == 1 ? '' : 's'}\x1b[0m");
}

void _printPrReviewCheckUsage() {
  print("Usage: gitty pr-review-check [--prune | -i]");
  print("");
  print("Finds the PR-<number> folders under ~/review-repos (as made by clone-pr) and");
  print("shows each pull request's URL, branch, author and current status, looked up with gh");
  print("from the repository cloned inside the folder. The Review column says");
  print("'requested' when the pull request is waiting on your review, such as after");
  print("the author re-requests it.");
  print("");
  print("Options:");
  print("  --prune     After the table, offer to delete the folders of merged and");
  print("              closed pull requests (and any parent folders left empty).");
  print("              Folders whose clone has uncommitted changes are kept.");
  print("  -i          Pick a pull request with the arrow keys (or j/k) and press");
  print("              Enter to run its resume.sh, o to open it in the browser, or");
  print("              b to copy its branch name; Esc or q exits.");
}

/// Options for the `squash` command.
class SquashOptions {
  final String message;
  final String? base;
  final bool force;
  final bool help;

  /// Set when the arguments could not be parsed; [message] is then empty.
  final String? error;

  SquashOptions({this.message = '', this.base, this.force = false, this.help = false, this.error});
}

/// Parses `squash` arguments: any number of message words plus the options
/// `--base <branch>`, `-f`/`--force` and `-h`/`--help`. `-m`/`-am` are ignored
/// so that a `git commit`-style invocation also works.
SquashOptions parseSquashArgs(List<String> args) {
  final words = <String>[];
  String? base;
  var force = false;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '-h':
      case '--help':
        return SquashOptions(help: true);
      case '-f':
      case '--force':
        force = true;
        break;
      case '-m':
      case '-am':
        break;
      case '--base':
        if (i + 1 >= args.length) {
          return SquashOptions(error: "Option '--base' requires a branch name");
        }
        base = args[++i];
        break;
      default:
        if (arg.startsWith('--base=')) {
          base = arg.substring('--base='.length);
          if (base.isEmpty) {
            return SquashOptions(error: "Option '--base' requires a branch name");
          }
          break;
        }
        if (arg.startsWith('-') && arg.length > 1) {
          return SquashOptions(error: "Unknown option '$arg'");
        }
        words.add(arg);
    }
  }

  final message = words.join(' ').trim();
  if (message.isEmpty) {
    return SquashOptions(error: 'Please specify a commit message');
  }
  return SquashOptions(message: message, base: base, force: force);
}

/// Returns true if [ref] resolves to a commit in this repository.
bool _refExists(String ref) {
  final result = Process.runSync('git', ['rev-parse', '--verify', '--quiet', '$ref^{commit}']);
  return result.exitCode == 0;
}

/// Finds the branch the current branch was cut from: the upstream of the
/// current branch if it is a different branch, otherwise the first of
/// `main`/`master` that exists locally.
String? _findBaseBranch(String currentBranch) {
  final upstream = Process.runSync('git', ['rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}'],
      stdoutEncoding: utf8);
  if (upstream.exitCode == 0) {
    final name = upstream.stdout.toString().trim();
    // The upstream of a pushed branch is itself; that is no help as a base.
    if (name.isNotEmpty && !name.endsWith('/$currentBranch')) {
      return name;
    }
  }

  for (final candidate in ['main', 'master']) {
    if (candidate != currentBranch && _refExists(candidate)) {
      return candidate;
    }
  }
  return null;
}

void _squashCommand(List<String> args) {
  final options = parseSquashArgs(args);
  if (options.help) {
    _printSquashUsage();
    return;
  }
  if (options.error != null) {
    print("\x1b[31mError: ${options.error}\x1b[0m");
    _printSquashUsage();
    exit(1);
  }

  final currentBranch = _executeGit(['branch', '--show-current']).trim();
  if (currentBranch.isEmpty) {
    print("\x1b[31mError: Not on any branch (detached HEAD)\x1b[0m");
    exit(1);
  }

  final base = options.base ?? _findBaseBranch(currentBranch);
  if (base == null) {
    print("\x1b[31mError: Unable to determine the base branch for '$currentBranch'\x1b[0m");
    print("Use 'gitty squash --base <branch> <message>' to specify it");
    exit(1);
  }
  if (base == currentBranch) {
    print("\x1b[31mError: Base branch and current branch are both '$currentBranch'\x1b[0m");
    exit(1);
  }
  if (!_refExists(base)) {
    print("\x1b[31mError: Base branch '$base' not found\x1b[0m");
    exit(1);
  }

  // Refuse to fold uncommitted work into the squashed commit.
  final dirty = _getGitStatus().where((s) => !s.isUntracked).toList();
  if (dirty.isNotEmpty) {
    print("\x1b[31mError: There are uncommitted changes:\x1b[0m");
    for (var status in dirty) {
      print("  \x1b[31m• ${status.path}\x1b[0m");
    }
    print("Commit or stash them before squashing");
    exit(1);
  }

  final mergeBase = _executeGit(['merge-base', base, 'HEAD']).trim();
  final commits = _executeGit(['log', '--format=%h %s', '$mergeBase..HEAD'])
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .toList();

  if (commits.isEmpty) {
    print("\x1b[33mNo commits on '$currentBranch' since '$base' - nothing to squash\x1b[0m");
    return;
  }
  if (commits.length == 1) {
    print("\x1b[33mOnly one commit on '$currentBranch' since '$base' - nothing to squash\x1b[0m");
    print("  ${commits[0]}");
    return;
  }

  print("Squashing ${commits.length} commits on \x1b[32m$currentBranch\x1b[0m since \x1b[32m$base\x1b[0m:");
  for (var commit in commits) {
    print("  $commit");
  }
  print("Into: \x1b[32m${options.message}\x1b[0m");

  if (!options.force) {
    if (!promptYes("Squash these ${commits.length} commits")) {
      print("Squash cancelled");
      return;
    }
  }

  _executeGit(['reset', '--soft', mergeBase]);
  final result = Process.runSync('git', ['commit', '-m', options.message], stdoutEncoding: utf8);
  if (result.exitCode != 0) {
    print("\x1b[31mError: Git commit failed\x1b[0m");
    print(result.stderr);
    print("The branch has been soft reset to $mergeBase; your changes are staged.");
    exit(1);
  }

  print("\x1b[32mSquashed ${commits.length} commits into one\x1b[0m");
  print(result.stdout);
  print("Note: history was rewritten; a pushed branch needs 'git push --force-with-lease'");
}

void _printSquashUsage() {
  print("Usage: gitty squash <message> [--base <branch>] [-f]");
  print("");
  print("Squashes the commits the current branch has since its base branch into a");
  print("single commit with the given message. Does nothing if there is only one.");
  print("");
  print("Options:");
  print("  --base <branch>   Branch to squash against (default: upstream, else main/master)");
  print("  -f, --force       Skip the confirmation prompt");
}

void _printUsage() {
  print("Usage: gitty <command> [options]");
  print("");
  print("Commands:");
  print("  status                              Check staging status");
  print("  stage                               Stage changes");
  print("  add <file1> [file2] ...             Add files to project allowlist");
  print("  rm <file1> [file2] ...              Remove files from project allowlist");
  print("  commit <message>                    Commit staged changes");
  print("  tag-today                           Create/update tag for today (vYYYY-MM-DD). Pushes to origin.");
  print("  snapshot                            Create a snapshot branch (snapshots/YYYY-MM-DD). Pushes to origin.");
  print("  move-tag <tag-name>                 Move specified tag to current commit");
  print("  clone-pr <pr-url> [--dir <dir>]     Clone a PR into ~/review-repos/<author>/<owner>/PR-<num>/<repo> (requires gh)");
  print("           [--claude]                 ...then run claude in it (writes ../resume.sh)");
  print("  clone-branch [-d] [--claude]        Clone the current (pushed) branch into ~/review-repos/local/<owner>/<branch>/<repo>");
  print("  pr-review-check [--prune | -i]      Show the status of each PR cloned under ~/review-repos (requires gh)");
  print("  squash <message> [--base <branch>]  Squash the current branch's commits into one");
  print("  projects <action>                   Manage projects");
  print("");
  print("Project actions:");
  print("  projects add                        Add current directory as project");
  print("  projects list                       List all configured projects");
  print("  projects get                        Show current project allowlist");
  print("  projects rm [-f]                    Remove current project from tracking");
  print("");
}

void process(List<String> args) {
  if (args.isEmpty) {
    _printUsage();
    return;
  }

  final command = args[0];
  final commandArgs = args.skip(1).toList();

  switch (command) {
    case 'stage':
      _stageCommand(true, commandArgs);
      break;

    case 'status':
      _stageCommand(false, commandArgs);
      break;

    case 'add':
      _addCommand(commandArgs);
      break;
    case 'rm':
      _rmCommand(commandArgs);
      break;
    case 'commit':
      _commitCommand(commandArgs);
      break;
    case 'projects':
      _projectsCommand(commandArgs);
      break;
    case 'move-tag':
      _moveTagCommand(commandArgs);
      break;
    case 'tag-today':
      tagTodayCommand(commandArgs);
      break;
    case 'snapshot':
      snapshotCommand(commandArgs);
      break;
    case 'clone-pr':
      _clonePrCommand(commandArgs);
      break;
    case 'clone-branch':
      _cloneBranchCommand(commandArgs);
      break;
    case 'pr-review-check':
      _prReviewCheckCommand(commandArgs);
      break;
    case 'squash':
      _squashCommand(commandArgs);
      break;

    default:
      print("\x1b[31mError: Unknown command '$command'\x1b[0m");
      _printUsage();
      exit(1);
  }
}
