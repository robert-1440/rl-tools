import 'dart:io';

import 'package:rl_tools/src/cli/util.dart';

bool exitMode = true;

class _Component {}

class _Comment extends _Component {
  final String _text;

  _Comment(String text) : _text = "$text\n";

  @override
  String toString() {
    return _text;
  }
}

class _Option extends _Component {
  final String key;

  String value;

  _Option(this.key, this.value);

  @override
  String toString() {
    return "$key=$value\n";
  }
}

class Section extends _Component {
  final String name;

  final List<_Component> _components = [];

  final Map<String, _Option> _options = {};

  Section._$(this.name);

  String getRequired(String name) {
    var v = this[name];
    if (v == null) {
      throw _fatal(("Unable to find '$name' in '${this.name}"));
    }
    return v;
  }

  bool containsAllKeys(Iterable<String> requiredKeys) {
    for (var key in requiredKeys) {
      if (!_options.containsKey(key)) {
        return false;
      }
    }
    return true;
  }

  bool containsKey(String key) {
    return _options.containsKey(key.toLowerCase());
  }

  String? remove(String key) {
    var o = _options.remove(key.toLowerCase());
    if (o == null) {
      return null;
    }
    _components.remove(o);
    return o.value;
  }

  String? set(String key, String value) {
    var o = _options[key.toLowerCase()];
    if (o == null) {
      o = _addOption(key, value);
      return null;
    }
    var oldValue = o.value;
    o.value = value;
    return oldValue;
  }

  String? operator [](String name) {
    var o = _options[name.toLowerCase()];
    return o?.value;
  }

  void _add(_Component component) {
    _components.add(component);
  }

  void _addComment(String text) {
    _add(_Comment(text));
  }

  _Option _addOption(String name, String value) {
    String key = name.toLowerCase();
    if (_options.containsKey(key)) {
      _fatal("key '$key' is duplicated in ${this.name} section.");
    }
    var o = _Option(name, value);
    _options[key] = o;
    _add(o);
    return o;
  }

  @override
  String toString() {
    var sb = StringBuffer();
    sb.writeln("[$name]");
    for (var c in _components) {
      sb.write(c);
    }
    return sb.toString();
  }

}

class _Builder {
  final Map<String, Section> sectionMap = {};

  final List<_Component> components = [];

  void parse(String text) {
    Section? section;
    int lineNumber = 1;
    for (var line in lineSplitter.convert(text)) {
      String stripped = line.trim();
      _Component? component;
      if (stripped.startsWith('[') && stripped.endsWith(']')) {
        String name = stripped.substring(1, stripped.length - 1);
        String key = name.toLowerCase();
        if (sectionMap.containsKey(key)) {
          _fatal(("Line $lineNumber: $name section is duplicated."));
        }
        section = Section._$(name);
        component = sectionMap[key] = section;
      } else if (section != null) {
        if (stripped.startsWith("#") || !stripped.contains("=")) {
          section._addComment(line);
        } else {
          var values = splitInTwo(stripped, "=");
          section._addOption(values[0], values[1]);
        }
      } else {
        component = _Comment(line);
      }
      if (component != null) {
        components.add(component);
      }
      lineNumber++;
    }
  }
}

class IniConfig {
  final Map<String, Section> _sectionMap;

  final List<_Component> _components;

  IniConfig(this._sectionMap, this._components);

  Section? operator [](String key) {
    return _sectionMap[key.toLowerCase()];
  }

  Section getSection(String sectionName) {
    var section = this[sectionName];
    if (section == null) {
      throw _fatal("Unable to find section '$sectionName'.");
    }
    return section;
  }

  Iterable<Section> get sections => _sectionMap.values;

  Section getOrAddSection(String sectionName) {
    return this[sectionName] ?? addSection(sectionName);
  }

  Section addSection(String sectionName) {
    var key = sectionName.toLowerCase();
    if (_sectionMap.containsKey(key)) {
      _fatal("'$sectionName' already exists");
    }
    var s = Section._$(sectionName);
    _sectionMap[key] = s;
    if (_components.isNotEmpty) {
      if (_components.last is! _Comment) {
        _components.add(_Comment(""));
      }
    }
    _components.add(s);
    return s;
  }

  String? set(String sectionName, String optionName, String value) {
    var section = this[sectionName] ?? addSection(sectionName);
    return section.set(optionName, value);
  }

  Section getRequired(String name, {String? thing}) {
    var v = this[name];
    if (v == null) {
      if (thing != null) {
        throw _fatal("Unable to find $thing '$name'.");
      }
      throw _fatal("Unable to find '$name'.");
    }
    return v;
  }

  @override
  String toString() {
    StringBuffer sb = StringBuffer();
    for (var c in _components) {
      sb.write(c);
    }
    return sb.toString();
  }
}

class IniFile extends IniConfig {
  final File file;

  IniFile.$(this.file, super.sectionMap, super.components);

  void save() {
    var parent = file.parent;
    if (!parent.existsSync()) {
      parent.create(recursive: true);
    }
    file.writeAsStringSync(toString());
  }
}

IniConfig parseString(String text) {
  var b = _Builder();
  b.parse(text);
  return IniConfig(b.sectionMap, b.components);
}

IniConfig createNew() => parseString("");

IniFile loadIniFile(String fileName, {bool mustExist = true}) {
  File file = File(fileName);
  if (!file.existsSync()) {
    if (mustExist) {
      throw _fatal("$fileName does not exit");
    }
    return IniFile.$(file, {}, []);
  }
  var b = _Builder();
  b.parse(file.readAsStringSync());
  return IniFile.$(file, b.sectionMap, b.components);
}

Exception _fatal(String message) {
  if (exitMode) {
    stderr.writeln(message);
    exit(2);
  }
  throw StateError(message);
}
