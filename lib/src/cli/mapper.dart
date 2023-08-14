import 'dart:collection';

class MapWrapper {
  final Map<String, dynamic> _source;

  MapWrapper._$(this._source);

  String getString(String key) {
    return get(key) as String;
  }

  String? findString(String key) {
    return _source[key] as String?;
  }

  Object get(String key) {
    var v = _source[key];
    if (v == null) {
      throw ArgumentError("$key does not exist.");
    }
    return v!;
  }

  dynamic operator [](String name) {
    return _source[name];
  }

  static MapWrapper of(Map<String, dynamic> map) {
    return MapWrapper._$(map);
  }
}

Set<T> toTreeSet<T>(Iterable<T> values) {
  var set = SplayTreeSet<T>();
  set.addAll(values);
  return set;
}
