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
  for (final arg in args) {
    if (arg == '-h' || arg == '--help') {
      _printClonePrUsage();
      return;
    }
    if (arg == '--claude') {
      launchClaude = true;
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
  if (positional.length > 2) {
    print("\x1b[31mError: Too many arguments\x1b[0m");
    _printClonePrUsage();
    exit(1);
  }

  final ref = parsePrRef(positional[0]);
  if (ref == null) {
    print("\x1b[31mError: '${positional[0]}' is not a recognized pull request reference\x1b[0m");
    print("Expected something like https://github.com/owner/repo/pull/123 or owner/repo#123");
    exit(1);
  }

  // Lay the clone out as <base>/<owner>/PR-<number>/<repo>.
  final baseDir = positional.length > 1 ? checkHomeInPath(positional[1]) : '';
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

  // Look up the PR first so we fail fast on a bad reference or missing auth.
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
    await _launchClaude(targetDir, ref.number);
  }
}

/// Runs `claude` in [dir] attached to this terminal, then exits with claude's
/// exit code. The session gets an ID chosen here so that a `resume.sh` next to
/// the repository can pick the review back up later, after first updating the
/// checkout to the pull request's latest commits.
Future<void> _launchClaude(String dir, int prNumber) async {
  final sessionId = _randomUuid();
  final resumeScript = File(_joinPath([Directory(dir).parent.path, 'resume.sh']));
  resumeScript.writeAsStringSync('#!/bin/sh\n'
      'cd ${_shellQuote(Directory(dir).absolute.path)} || exit 1\n'
      'gh pr checkout $prNumber --force || exit 1\n'
      'exec claude --resume $sessionId "\$@"\n');
  Process.runSync('chmod', ['+x', resumeScript.path]);
  print("Wrote '${resumeScript.path}' to resume this session");

  print("Starting 'claude' in '$dir'...");
  final Process process;
  try {
    process = await Process.start('claude', ['--session-id', sessionId],
        workingDirectory: dir, mode: ProcessStartMode.inheritStdio);
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
  print("Usage: gitty clone-pr [--claude] <pr-url> [base-dir]");
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
  print("The base directory defaults to the current directory.");
  print("");
  print("Options:");
  print("  --claude    After checkout, run 'claude' in the cloned repository;");
  print("              gitty exits when claude does. Also writes an executable");
  print("              <base-dir>/<owner>/PR-<number>/resume.sh that updates the");
  print("              checkout to the PR's latest commits and resumes that");
  print("              claude session.");
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
  print("  clone-pr <pr-url> [base-dir]        Clone a PR into <owner>/PR-<num>/<repo> and check it out (requires gh)");
  print("           [--claude]                 ...then run claude in it (writes ../resume.sh)");
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
    case 'squash':
      _squashCommand(commandArgs);
      break;

    default:
      print("\x1b[31mError: Unknown command '$command'\x1b[0m");
      _printUsage();
      exit(1);
  }
}
