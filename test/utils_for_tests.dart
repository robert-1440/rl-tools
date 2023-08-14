import 'dart:collection';
import 'dart:mirrors';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

final _nullValueRef = ObjectReference.of(null);

final emptyList = List.unmodifiable([]);

class ObjectReference<T> {
  final T? _value;

  ObjectReference._internal(this._value);

  static ObjectReference<T> of<T>(T? value) {
    return ObjectReference._internal(value);
  }

  T? get() => _value;

  static T? valueFor<T>(ObjectReference<T?>? ref) {
    return ref?._value;
  }

  static ObjectReference<T> nullRef<T>() {
    return _nullValueRef as dynamic;
  }
}

class KeyId {
  final List<dynamic> argList;

  final int _hash;

  KeyId(this.argList) : _hash = _computeHash(argList);

  @override
  int get hashCode => _hash;

  @override
  bool operator ==(Object other) {
    if (other is KeyId && other.argList.length == argList.length) {
      for (int i = 0; i < argList.length; i++) {
        if (!_equals(argList[i], other.argList[i])) {
          return false;
        }
      }
      return true;
    }
    return false;
  }
}

int _computeHash(List<dynamic> list) {
  int result = 59;
  for (var v in list) {
    if (v != null) {
      result += v.hashCode;
    }
  }
  return result;
}

bool _equals(dynamic a, dynamic b) {
  if (a == null) {
    return b == null;
  }
  if (b == null) {
    return false;
  }
  if (a is Map) {
    if (b is Map) {
      if (a.length != b.length) {
        return false;
      }
      for (var entry in a.entries) {
        var that = b[entry.key];
        if (that == null) {
          if (!b.containsKey(entry.key)) {
            return false;
          }
        }
        if (!_equals(entry.value, that)) {
          return false;
        }
      }
    }
    return true;
  }

  return a == b;
}

bool objectsEqual(dynamic a, dynamic b) {
  return _equals(a, b);
}

class BeforeAll {
  final String name;

  const BeforeAll(this.name);
}

class AfterAll {
  final String name;

  const AfterAll(this.name);
}

class BeforeEach {
  final String name;

  const BeforeEach(this.name);
}

class AfterEach {
  final String name;

  const AfterEach(this.name);
}

class Test {
  final String name;

  const Test(this.name);
}

class Entry {
  final String name;

  final Symbol symbol;

  Entry(this.name, this.symbol);
}

class StaticEntry {
  final ClassMirror mirror;

  final Symbol symbol;

  StaticEntry(this.mirror, this.symbol);

  void invoke() {
    mirror.invoke(symbol, emptyList);
  }
}

final defaultConstructorSymbol = Symbol("");

class TestRunner {
  final LinkedHashSet<Entry> _entries = LinkedHashSet();

  final LinkedHashSet<StaticEntry> beforeAll = LinkedHashSet();

  final LinkedHashSet<StaticEntry> afterAll = LinkedHashSet();

  final LinkedHashSet<Symbol> beforeEach = LinkedHashSet();

  final LinkedHashSet<Symbol> afterEach = LinkedHashSet();

  late ClassMirror classMirror;

  int runningCount = 0;

  TestRunner(Type classType) {
    ClassMirror? mirror = classMirror = reflectClass(classType);
    while (mirror != null) {
      _process(mirror);
      mirror = mirror.superclass;
    }

    assert(_entries.isNotEmpty, "No tests found.");
  }

  void _process(ClassMirror classMirror) {
    for (var m in classMirror.declarations.values) {
      if (m is MethodMirror) {
        if (m.isStatic) {
          for (var mirror in m.metadata) {
            var meta = mirror.reflectee;
            if (meta is BeforeAll) {
              beforeAll.add(StaticEntry(classMirror, m.simpleName));
            } else if (meta is AfterAll) {
              afterAll.add(StaticEntry(classMirror, m.simpleName));
            } else if (meta is BeforeEach || meta is AfterEach) {
              throw StateError(
                  "${classMirror.reflectedType}:${MirrorSystem.getName(m.simpleName)} @${meta.runtimeType}  can only be used on non-static methods.");
            }
          }
          continue;
        }
        if (!m.isConstructor) {
          for (var mirror in m.metadata) {
            var meta = mirror.reflectee;
            if (meta is BeforeEach) {
              beforeEach.add(m.simpleName);
            } else if (meta is AfterEach) {
              afterEach.add(m.simpleName);
            } else if (meta is Test) {
              _entries.add(Entry(meta.name, m.simpleName));
            } else if (meta is BeforeAll || meta is AfterAll) {
              throw StateError(
                  "${classMirror.reflectedType}:${MirrorSystem.getName(m.simpleName)} @${meta.runtimeType} can only be used on static methods.");
            }
          }
        }
      }
    }
  }

  void _runTests([String? testNameToRun]) {
    _invokeAllStatic(beforeAll);
    for (var entry in _entries.where((element) => testNameToRun == null || element.name == testNameToRun)) {
      runningCount++;
      test(entry.name, () async => await executeTest(entry));
    }
  }

  void _invokeAllStatic(Iterable<StaticEntry> entries) {
    for (var entry in entries) {
      entry.invoke();
    }
  }

  void _invokeAll(ObjectMirror mirror, Iterable<Symbol> symbols) {
    for (var symbol in symbols) {
      mirror.invoke(symbol, emptyList);
    }
  }

  Future<void> executeTest(Entry entry) async {
    var instance = classMirror.newInstance(defaultConstructorSymbol, emptyList).reflectee;
    var ref = reflect(instance);
    _invokeAll(ref, beforeEach);

    try {
      await ref.invoke(entry.symbol, emptyList).reflectee;
    } finally {
      _invokeAll(ref, afterEach);
      if (--runningCount < 1) {
        _invokeAllStatic(afterAll);
      }
    }
  }
}

class Assertion<T> {
  final T? _actualValue;

  Assertion(this._actualValue);

  Assertion<T> isEqualTo(T? value) {
    expect(_actualValue, value);
    return this;
  }

  bool _getBool() {
    isNotNull();
    if (_actualValue is bool) {
      return _actualValue as bool;
    }
    throw AssertionError("$_actualValue (type=${_actualValue?.runtimeType})is not a boolean.");
  }

  Map _getMap() {
    isNotNull();
    if (_actualValue is Map) {
      return _actualValue as Map;
    }
    throw AssertionError("$_actualValue (type=${_actualValue?.runtimeType})is not a map.");
  }

  Assertion<T> isTrue() {
    if (!_getBool()) {
      throw AssertionError("Expected value to be true");
    }
    return this;
  }

  Assertion<T> isFalse() {
    if (_getBool()) {
      throw AssertionError("Expected value to be false");
    }
    return this;
  }

  Assertion<T> hasEntry<K, V>(K key, V value) {
    var m = _getMap();
    var actualValue = m[key];
    if (actualValue == null && !m.containsKey(key)) {
      throw AssertionError("Actual does not contain $key. Values: $actualValue");
    }
    if (!objectsEqual(actualValue, value)) {
      throw AssertionError("Expected '$key' to equal $value, but was $actualValue");
    }
    return this;
  }

  Assertion<T> isNull() {
    if (_actualValue != null) {
      throw AssertionError("Expected null but got <$_actualValue>");
    }
    return this;
  }

  Assertion<T> isNotNull() {
    if (_actualValue == null) {
      throw AssertionError("Expected value to not be null");
    }
    return this;
  }

  Assertion<T> contains(String text) {
    isNotNull();
    assert(_actualValue is String);
    String actualText = _actualValue as String;
    if (!actualText.contains(text)) {
      throw AssertionError("Expected '$_actualValue' to contain '$text'.");
    }
    return this;
  }

  Assertion<T> isEmpty() {
    if (_getSize() != 0) {
      throw AssertionError("Expected '$_actualValue' to be empty.");
    }
    return this;
  }

  int _getSize() {
    isNotNull();

    var v = _actualValue as dynamic;
    return v.length;
  }

  Assertion<T> hasSize(int size) {
    int actualSize = _getSize();
    if (actualSize != size) {
      throw AssertionError("Expected size of $size, got: $actualSize");
    }
    return this;
  }

  Assertion<T> isGreaterThan(dynamic value) {
    isNotNull();
    if (value >= _actualValue) {
      throw AssertionError("Expected $_actualValue to be greater than $value.");
    }
    return this;
  }

  Assertion<T> hasMessage(String expected) {
    isNotNull();
    dynamic message = getField(_actualValue, "message");
    if (message != expected) {
      throw AssertionError("Expected exception message to be '$expected', but was '$message'");
    }
    return this;
  }

  Assertion<T> hasMessageContaining(String expected) {
    isNotNull();
    dynamic message = getField(_actualValue, "message");
    if (!message.contains(expected)) {
      throw AssertionError("Expected exception message '$message' to contain '$expected'");
    }
    return this;
  }
}

Assertion<T> assertThat<T>(T? value) {
  return Assertion(value);
}

Future<T> assertThrowsAsync<T>(Type exceptionType, Function function) async {
  dynamic result;
  try {
    result = await function();
  } catch (ex) {
    if (isInstance(exceptionType, ex)) {
      return ex as T;
    }
    throw AssertionError("Expected an exception of type $exceptionType to be thrown, but a ${ex.runtimeType} was thrown.");
  }
  if (result is Future) {
    result.then((value) => null).onError((error, stackTrace) => null);
    throw AssertionError("Function provided ($function) returned a future, use assertThrowsAsync() instead.");
  }
  throw AssertionError("Expected an exception of type $exceptionType to be thrown.");
}

T assertThrows<T>(Type exceptionType, Function function) {
  dynamic result;
  try {
    result = function();
  } catch (ex) {
    if (isInstance(exceptionType, ex)) {
      return ex as T;
    }
    throw AssertionError("Expected an exception of type $exceptionType to be thrown, but a ${ex.runtimeType} was thrown.");
  }
  if (result is Future) {
    result.then((value) => null).onError((error, stackTrace) => null);
    throw AssertionError("Function provided ($function) returned a future, use assertThrowsAsync() instead.");
  }
  throw AssertionError("Expected an exception of type $exceptionType to be thrown.");
}

bool isInstance(Type runtimeType, dynamic instance) {
  if (instance == null) {
    return false;
  }
  ClassMirror? mirror = reflectClass(runtimeType);
  while (mirror != null) {
    if (mirror.reflectedType == instance.runtimeType) {
      return true;
    }
    mirror = mirror.superclass;
  }
  return false;
}

void executeTestSuite(Type classType, [String? testNameToRun]) {
  TestRunner(classType)._runTests(testNameToRun);
}

dynamic getField(dynamic object, String fieldName) {
  var m = reflect(object);
  return m.getField(Symbol(fieldName)).reflectee;
}

void setField(dynamic object, String fieldName, dynamic value) {
  var m = reflect(object);
  m.setField(Symbol(fieldName), value);
}
