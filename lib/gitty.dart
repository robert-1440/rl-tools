import 'dart:io';

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

void _commitCommand(List<String> args) {
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

void _executeGit(List<String> args) {
  final result = Process.runSync('git', args);
  if (result.exitCode != 0) {
    print("\x1b[31mError: Git command failed\x1b[0m");
    print(result.stderr);
    exit(1);
  }
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

void _printUsage() {
  print("Usage: gitty <command> [options]");
  print("");
  print("Commands:");
  print("  status                              Check staging status");
  print("  stage                               Stage changes");
  print("  add <file1> [file2] ...             Add files to project allowlist");
  print("  rm <file1> [file2] ...              Remove files from project allowlist");
  print("  commit <message>                    Commit staged changes");
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
    default:
      print("\x1b[31mError: Unknown command '$command'\x1b[0m");
      _printUsage();
      exit(1);
  }
}
