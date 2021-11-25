
import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/cupertino.dart';
import 'package:js_script/types.dart';

import 'common.dart';
import 'js_ffi.dart';
import 'js_script.dart';
import 'package:path/path.dart' as path;

class IOJsValue extends JsValue {
  final IOJsScript script;
  final Pointer _ptr;
  bool _disposed = false;

  // New a pure JS object
  IOJsValue._js(this.script, this._ptr) : super(
    dartObject: null,
    type: JsValueType.JsObject,
  ) {
    script._cache.add(this);
    _retainCount = 1;
    delayRelease();
  }

  // New a JS object and bind with a dart object.
  IOJsValue._instance(this.script, this._ptr, dartObject) : super(
    dartObject: dartObject,
    type: JsValueType.DartInstance,
  ) {
    script._cache.add(this);
    _retainCount = 1;
    delayRelease();
  }

  // New a JS object and bind with a dart type.
  IOJsValue._class(this.script, this._ptr, dartObject) : super(
    dartObject: dartObject,
    type: JsValueType.DartClass,
  ) {
    script._cache.add(this);
    _retainCount = 1;
    delayRelease();
  }

  int _retainCount = 0;
  void onDispose() {
    assert(!_disposed);
    binder.releaseValue(script._context, _ptr);
    script._cache.remove(this);
    _disposed = true;
  }

  // retain count +1
  int retain() {
    return ++_retainCount;
  }

  // retain count -1 when retain count <= 0 dispose this object.
  int release() {
    if (--_retainCount <= 0) {
      if (!_disposed)
        onDispose();
    }
    return _retainCount;
  }

  // release this after 30ms.
  void delayRelease() {
    Future.delayed(Duration(milliseconds: 30), () {
      release();
    });
  }

  void _internalDispose() {
    binder.releaseValue(script._context, _ptr);
    _disposed = true;
  }

  /// Set property to this JS object.
  ///
  /// The [key] would be a String or int value
  ///
  /// The [value] could be one of [int], [double], [bool],
  /// [String], [Future] and [JsValue]
  void set(dynamic key, dynamic value) {
    assert(!_disposed);
    script._arguments[0].setValue(this);
    if (key is String) {
      script._arguments[1].setString(key, script);
    } else if (key is int) {
      script._arguments[1].setInt(key);
    } else {
      throw Exception("key must be a String or int");
    }
    script._arguments[2].set(value, script);
    script._action(JS_ACTION_SET, 3);
  }

  /// Get a property of this JS object.
  ///
  /// The result could be one of [int], [double], [bool],
  /// [String] and [JsValue]
  dynamic get(dynamic key) {
    assert(!_disposed);
    script._arguments[0].setValue(this);
    if (key is String) {
      script._arguments[1].setString(key, script);
    } else if (key is int) {
      script._arguments[1].setInt(key);
    } else {
      throw Exception("key must be a String or int");
    }
    return script._action(JS_ACTION_GET, 2, block: (results, length) => results[0].get(script));
  }

  operator[]= (dynamic key, dynamic value) => set(key, value);
  operator[] (dynamic key) => get(key);

  /// Invoke a property function.
  dynamic invoke(String name, [List argv = const [],]) {
    assert(!_disposed);
    int len = argv.length;
    if (len > MAX_ARGUMENTS - 3) {
      throw Exception("The arguments are too many ${MAX_ARGUMENTS - 3}");
    }
    script._arguments[0].setValue(this);
    script._arguments[1].setString(name, script);
    script._arguments[2].setInt(argv.length);
    for (int i = 0, t = len; i < t; ++i) {
      script._arguments[i + 3].set(argv[i], script);
    }
    return script._action(JS_ACTION_INVOKE, 3 + len,
        block: (results, length) => results[0].get(script));
  }

  /// Call as a JS function object.
  dynamic call([List argv = const []]) {
    assert(!_disposed);
    int len = argv.length;
    if (len > MAX_ARGUMENTS - 2) {
      throw Exception("The arguments are too many ${MAX_ARGUMENTS - 3}");
    }
    script._arguments[0].setValue(this);
    script._arguments[1].setInt(argv.length);
    for (int i = 0, t = len; i < t; ++i) {
      script._arguments[i + 2].set(argv[i], script);
    }
    return script._action(JS_ACTION_CALL, 2 + len,
        block: (results, length) => results[0].get(script)
    );
  }

  bool get isArray {
    script._arguments[0].setValue(this);
    return script._action(JS_ACTION_IS_ARRAY, 1, block: (results, length) => results[0].get(script));
  }

  bool get isFunction {
    script._arguments[0].setValue(this);
    return script._action(JS_ACTION_IS_FUNCTION, 1, block: (results, length) => results[0].get(script));
  }

  bool get isConstructor {
    script._arguments[0].setValue(this);
    return script._action(JS_ACTION_IS_CONSTRUCTOR, 1, block: (results, length) => results[0].get(script));
  }

  Future get asFuture {
    assert(!_disposed);
    Completer completer = Completer();
    JsValue resolve = script.function((argv) => completer.complete(argv[0]));
    JsValue reject = script.function((argv) => completer.completeError(argv[0]));
    script._arguments[0].setValue(this);
    script._arguments[1].setValue(resolve as IOJsValue);
    script._arguments[2].setValue(reject as IOJsValue);
    script._action(JS_ACTION_RUN_PROMISE, 3);
    return completer.future;
  }

  List<String> getOwnPropertyNames() {
    assert(!_disposed);
    script._arguments[0].setValue(this);
    return script._action(JS_ACTION_PROPERTY_NAMES, 1, block: (results, length) {
      String ret = results[0].get(script);
      return ret.split(",");
    });
  }

  @override
  String toString() {
    if (_disposed) {
      return "[Disposed JsValue]";
    } else {
      script._arguments[0].setValue(this);
      return script._action(JS_ACTION_TO_STRING, 1, block: (results, length) {
        var arg = results[0];
        if (arg.type == ARG_TYPE_STRING) {
          String str = arg.get(script);
          binder.freeStringPtr(script._context, arg.ptrValue);
          return str;
        } else {
          throw Exception("Unkown Error toString()");
        }
      });
    }
  }

  @override
  bool operator ==(Object other) {
    if (other is IOJsValue)
      return other._ptr == _ptr;
    return super == other;
  }

  @override
  int get hashCode => 0x7a00000 | _ptr.address;

}

void _printHandler(int type, Pointer<Utf8> str) {
  switch (type)
  {
    case 0:
      print("[Js:Log] ${str.toDartString()}");
      break;
    case 1:
      print("[Js:Warn] ${str.toDartString()}");
      break;
    case 2:
      print("[Js:Error] ${str.toDartString()}");
      break;
  }
}

int _toDartHandler(Pointer context, int type, int argc) {
  var script = IOJsScript._index[context];
  if (script != null) {
    return script._toDartAction(type, argc);
  }
  return -2;
}

class IOJsCompiled extends JsCompiled {
  Pointer pointer;
  int length;

  IOJsCompiled(this.pointer, this.length);

  @override
  void dispose() {
    malloc.free(pointer);
  }
}

const int _Result = -2;
Pointer<NativeFunction<JsPrintHandlerFunc>> _printHandlerPtr = Pointer.fromFunction(_printHandler);
Pointer<NativeFunction<JsToDartActionFunc>> _toDartHandlerPtr = Pointer.fromFunction(_toDartHandler, _Result);

class _ClassInfo {
  ClassInfo clazz;
  int index;
  Pointer ptr;

  _ClassInfo(this.clazz, this.index, this.ptr);
}

class IOJsBuffer extends JsBuffer {
  IOJsScript script;
  late Pointer<Uint8> memory;

  late JsValue value;

  IOJsBuffer(this.script, int length) : super(length) {
    memory = malloc.allocate(length);

    script._arguments[0].setInt(length);
    script._arguments[1].type = ARG_TYPE_RAW_POINTER;
    script._arguments[1].ptrValue = memory;
    value = script._action(JS_ACTION_NEW_ARRAYBUFFER, 2, block: (results, len) {
      if (len == 1 && results[0].type == ARG_TYPE_RAW_POINTER) {
        Pointer rawPtr = results[0].ptrValue;
        var ptr = binder.retainValue(script._context, rawPtr);
        return IOJsValue._js(script, ptr.ref.ptrValue);
      } else {
        throw Exception("Wrong result");
      }
    });
  }

  @override
  void fill(Uint8List buffer, int offset) {
    var memBuffer = memory.asTypedList(length);
    memBuffer.setRange(offset, offset + buffer.length, buffer);
  }

}

class IOJsScript extends JsScript {
  static HashMap<Pointer, IOJsScript> _index = HashMap();

  Pointer<JsArgument> _rawArguments;
  Pointer<JsArgument> _rawResults;

  List<JsArgument> _arguments = [];
  List<JsArgument> _results = [];
  late Pointer _context;

  List<IOJsValue> _cache = [];
  Map<Pointer, dynamic> _instances = {};
  List<Pointer> _cachePromises = [];

  final int maxArguments;

  bool _disposed = false;
  void Function(String)? onUncaughtError;

  IOJsScript({
    this.maxArguments = MAX_ARGUMENTS,
    this.onUncaughtError,
    fileSystems = const []
  }) : _rawArguments = malloc.allocate(maxArguments * sizeOf<JsArgument>()),
        _rawResults = malloc.allocate(maxArguments * sizeOf<JsArgument>()),
        super.init(fileSystems: fileSystems) {
    for (int i = 0; i < maxArguments; ++i) {
      _arguments.add(_rawArguments[i]);
    }
    for (int i = 0; i < maxArguments; ++i) {
      _results.add(_rawResults[i]);
    }

    Pointer<JsHandlers> handlers = malloc.allocate(sizeOf<JsHandlers>());
    handlers.ref.maxArguments = maxArguments;
    handlers.ref.print = _printHandlerPtr;
    handlers.ref.toDartAction = _toDartHandlerPtr;
    _context = binder.setupJsContext(_rawArguments, _rawResults, handlers);
    _index[_context] = this;
    malloc.free(handlers);
    addClass(ClassInfo<Object>(
      name: "DartObject",
      newInstance: (_, argv) => Object(),
    ));
    addClass(mapClass);
    addClass(listClass);
  }

  List<_ClassInfo> _classList = [];
  Map<Type, _ClassInfo> _classIndex = {};

  /// Define a bound class in the JS context.
  void addClass(ClassInfo clazz) {
    int index = _classList.length;
    var jsClass = clazz.createJsClass();
    Pointer ptr = binder.registerClass(_context, jsClass, index);
    clazz.deleteJsClass(jsClass);
    var classIndex = _ClassInfo(clazz, index, ptr);
    _classList.add(classIndex);
    _classIndex[clazz.type] = classIndex;
  }

  /// Shutdown this JS context.
  void dispose() {
    for (var promise in _cachePromises) {
      _arguments[0].type = ARG_TYPE_PROMISE;
      _arguments[0].ptrValue = promise;
      _arguments[1].setInt(2);
      _action(JS_ACTION_PROMISE_COMPLETE, 2);
    }
    _cachePromises.clear();
    for (var val in _cache) {
      val._internalDispose();
    }
    _cache.clear();
    _clearTemporary();
    _wrapper?.release();
    binder.clearCache(_context);
    binder.deleteJsContext(_context);
    _index.remove(_context);
    malloc.free(_rawArguments);
    malloc.free(_rawResults);
    _disposed = true;
  }

  eval(String script, [String filepath = "<inline>"]) {
    _arguments[0].setString(script, this);
    _arguments[1].setString(filepath, this);
    return _action(JS_ACTION_EVAL, 2, block: (results, length) => results[0].get(this));
  }

  /// Run a JS script which would be find from [fileSystems], and
  /// the script would be treat as a module.
  ///
  /// The result is the default module exports.
  run(String filepath) {
    String? path = fileSystems.findPath("/", filepath);
    if (path != null) {
      String? code = fileSystems.loadCode(path);
      if (code != null) {
        _arguments[0].setString(code, this);
        _arguments[1].setString(path, this);
        return _action(JS_ACTION_RUN, 2, block: (results, length) => results[0].get(this));
      }
    }
    throw Exception("File not found. $filepath");
  }

  List<Pointer> _temp = [];

  void _clearTemporary() {
    for (var ptr in _temp) {
      malloc.free(ptr);
    }
    _temp.clear();
  }

  bool _waitForClear = false;
  void _needClearTemporary() {
    if (_waitForClear) return;
    _waitForClear = true;
    Future.delayed(Duration(milliseconds: 0)).then((value) {
      _clearTemporary();
      _waitForClear = false;
    });
  }

  dynamic _action(int type, int argc, {
    Function(List<JsArgument> results, int length)? block,
  }) {
    int len = binder.action(_context, type, argc);
    _needClearTemporary();
    if (len < 0) {
      throw Exception(_results[0].get(this));
    }
    var ret = block?.call(_results, len);
    binder.clearCache(_context);
    if (binder.hasPendingJob(_context) != 0) {
      Future.delayed(Duration.zero, _nextStep);
    }
    return ret;
  }

  void _nextStep() {
    if (_disposed) return;
    while (true) {
      int ret = binder.executePendingJob(_context);
      if (ret == 0) return;
      else if (ret < 0) {
        String str = _results[0].get(this);
        if (onUncaughtError == null) {
          print("Uncaught $str");
        } else {
          onUncaughtError!(str);
        }
      }
    }
  }

  List _tempArgv = [];
  int _toDartAction(int type, int argc) {
    try {
      switch (type) {
        case DART_ACTION_CONSTRUCTOR: {
          if (argc >= 2 && _arguments[0].isInt && _arguments[1].type == ARG_TYPE_RAW_POINTER) {
            var clazz = _classList[_arguments[0].intValue].clazz;
            Pointer ptr = _arguments[1].ptrValue;
            _tempArgv.length = argc - 2;
            for (int i = 0, t = _tempArgv.length; i < t; ++i) {
              _tempArgv[i] = _arguments[2 + i].get(this);
            }
            var ins = clazz.members[0].call(this, _tempArgv);
            _instances[ptr] = ins;
            return 0;
          } else {
            _results[0].setString("Wrong arguments", this);
            return -1;
          }
        }
        case DART_ACTION_CALL: {
          if (argc >= 2 && _arguments[0].isInt && _arguments[1].isInt) {
            var clazz = _classList[_arguments[0].intValue].clazz;
            var member = clazz.members[_arguments[1].intValue];

            if (member.type & MEMBER_STATIC == 0) {
              if (_arguments[2].type == ARG_TYPE_RAW_POINTER) {
                var obj = _instances[_arguments[2].ptrValue];
                if (obj != null) {
                  _tempArgv.length = argc - 3;
                  for (int i = 0, t = _tempArgv.length; i < t; ++i) {
                    _tempArgv[i] = _arguments[3 + i].get(this);
                  }
                  _results[0].set(member.call(obj, _tempArgv), this);
                  return 1;
                } else {
                  _results[0].setString("Target not found.", this);
                  return -1;
                }
              } else {
                _results[0].setString("Wrong arguments", this);
                return -1;
              }
            } else {
              int len = argc - 2;
              if (len != _tempArgv.length)
                _tempArgv.length = len;
              for (int i = 0, t = _tempArgv.length; i < t; ++i) {
                _tempArgv[i] = _arguments[2 + i].get(this);
              }
              _results[0].set(member.call(null, _tempArgv), this);
              return 1;
            }
          } else {
            _results[0].setString("Wrong arguments", this);
            return -1;
          }
        }
        case DART_ACTION_DELETE: {
          if (argc == 1 && _arguments[0].type == ARG_TYPE_RAW_POINTER) {
            Pointer pointer = _arguments[0].ptrValue;
            if (_instances.containsKey(pointer)) {
              var ins = _instances.remove(pointer);
              if (ins is JsDispose) ins.dispose();
              return 0;
            } else {
              _results[0].setString("Target not found.", this);
              return -1;
            }
          } else {
            _results[0].setString("Wrong arguments", this);
            return -1;
          }
        }
        case DART_ACTION_CALL_FUNCTION: {
          if (argc >= 1 && _arguments[0].type == ARG_TYPE_RAW_POINTER) {
            Pointer pointer = _arguments[0].ptrValue;
            var func = _instances[pointer];
            if (func != null && func is Function(List)) {
              _tempArgv.length = argc - 1;
              for (int i = 0, t = _tempArgv.length; i < t; ++i) {
                _tempArgv[i] = _arguments[1 + i].get(this);
              }
              _results[0].set(func(_tempArgv), this);
              return 1;
            } else {
              _results[0].setString("Target not found.", this);
              return -1;
            }
          } else {
            _results[0].setString("Wrong arguments", this);
            return -1;
          }
        }
        case DART_ACTION_MODULE_NAME: {
          if (argc == 2 &&
              _arguments[0].type == ARG_TYPE_STRING &&
              _arguments[1].type == ARG_TYPE_STRING) {
            String basename = _arguments[0].get(this);
            String module = _arguments[1].get(this);
            String? ret = fileSystems.findPath(basename, module);
            if (ret == null) {
              return 0;
            }
            _results[0].setString(ret, this);
            return 1;
          } else {
            _results[0].setString("Wrong arguments", this);
            return -1;
          }
        }
        case DART_ACTION_LOAD_MODULE: {
          if (argc == 1 &&
              _arguments[0].type == ARG_TYPE_STRING) {
            String filename = _arguments[0].get(this);
            var code = fileSystems.loadCode(filename);
            if (code != null) {
              _results[0].setString(code, this);
              return 1;
            } else {
              return 0;
            }
          } else {
            _results[0].setString("Wrong arguments", this);
            return -1;
          }
        }
        case DART_ACTION_MODULE_NAME: {
          if (argc == 2 &&
              _arguments[0].type == ARG_TYPE_STRING &&
              _arguments[1].type == ARG_TYPE_STRING) {
            String basename = _arguments[0].get(this);
            String module = _arguments[0].get(this);
            String? result = fileSystems.findPath(basename, module);
            if (result != null) {
              _results[0].setString(result, this);
              return 1;
            } else {
              return 0;
            }
          } else {
            _results[0].setString("Wrong arguments", this);
            return -1;
          }
        }
      }
      _results[0].setString("Not implemented", this);
      return -1;
    } catch (e, stack) {
      _results[0].setString("$e\n$stack", this);
      return -1;
    }
  }

  /// Establish a binding relationship between dart and js object
  JsValue bind(dynamic object, {
    ClassInfo? classInfo,
    JsValue? classFunc,
  }) {
    if (object == null)
      throw Exception("Object is null");
    Pointer classPtr;
    if (classFunc == null) {
      if (classInfo == null) {
        classPtr = _classList[0].ptr;
      } else {
        if (_classIndex.containsKey(classInfo.type)) {
          classPtr = _classIndex[classInfo.type]!.ptr;
        } else {
          addClass(classInfo);
          classPtr = _classList.last.ptr;
        }
      }
    } else {
      classPtr = (classFunc as IOJsValue)._ptr;
    }

    _arguments[0].type = ARG_TYPE_MANAGED_VALUE;
    _arguments[0].ptrValue = classPtr;
    return _action(JS_ACTION_BIND, 1,
      block: (results, len) {
        if (len == 1 && results[0].type == ARG_TYPE_RAW_POINTER) {
          Pointer rawPtr = results[0].ptrValue;
          _instances[rawPtr] = object;
          var ptr = binder.retainValue(_context, rawPtr);
          return IOJsValue._js(this, ptr.ref.ptrValue);
        } else {
          throw Exception("Wrong result");
        }
      },
    );
  }

  Pointer _newPromise(Future future) {
    Pointer promise = binder.newPromise(_context);
    if (promise.address == 0) {
      throw Exception(_results[0].get(this));
    }
    promiseComplete(bool success, dynamic object) {
      if (_disposed) return;
      if (_cachePromises.contains(promise)) {
        _arguments[0].type = ARG_TYPE_PROMISE;
        _arguments[0].ptrValue = promise;
        _arguments[1].setInt(success ? 1 : 0);
        _arguments[2].set(object, this);
        _action(JS_ACTION_PROMISE_COMPLETE, 3);
        _cachePromises.remove(promise);
      }
    }
    _cachePromises.add(promise);
    future.then((value) {
      promiseComplete(true, value);
    }).catchError((error, stack) {
      promiseComplete(false, "${error.toString()}\n$stack");
    });
    return promise;
  }

  /// Send a dart callback to JS context.
  JsValue function(Function(List argv) func) {
    return _action(JS_ACTION_WRAP_FUNCTION, 0, block: (results, len) {
      if (len == 1 && results[0].type == ARG_TYPE_RAW_POINTER) {
        Pointer rawPtr = results[0].ptrValue;
        _instances[rawPtr] = func;
        var ptr = binder.retainValue(_context, rawPtr);
        return IOJsValue._instance(this, ptr.ref.ptrValue, func);
      } else {
        throw Exception("Wrong result");
      }
    });
  }

  JsValue newObject() {
    return _action(JS_ACTION_NEW_OBJECT, 0,
      block: (results, len) {
        if (len == 1 && results[0].type == ARG_TYPE_RAW_POINTER) {
          Pointer rawPtr = results[0].ptrValue;
          var ptr = binder.retainValue(_context, rawPtr);
          return IOJsValue._js(this, ptr.ref.ptrValue);
        } else {
          throw Exception("Wrong result");
        }
      },
    );
  }

  JsValue newArray() {
    return _action(JS_ACTION_NEW_ARRAY, 0,
      block: (results, len) {
        if (len == 1 && results[0].type == ARG_TYPE_RAW_POINTER) {
          Pointer rawPtr = results[0].ptrValue;
          var ptr = binder.retainValue(_context, rawPtr);
          return IOJsValue._js(this, ptr.ref.ptrValue);
        } else {
          throw Exception("Wrong result");
        }
      },
    );
  }

  JsValue? _wrapper;
  JsValue collectionWrap(JsValue value) {
    if (_wrapper == null) {
      _wrapper = eval("""
(function() {
    const handler = {
        get: function(obj, prop) {
            if (prop === 'length')
                return obj.length;
            if (prop === 'toJSON') 
                return function() {return obj.toJSON(obj);};
            return obj.get(prop);
        },
        set: function(obj, prop, value) {
            if (prop == 'length')
                obj.length = value;
            obj.set(prop, value);
        }
    };
    return function(target) {
        return new Proxy(target, handler);
    };
})()
      """);
      _wrapper!.retain();
    }
    return _wrapper!.call([value]);
  }

  @override
  JsBuffer newBuffer(int length) {
    if (_disposed) {
      throw Exception("Js context is already disposed.");
    }
    return IOJsBuffer(this, length);
  }

  JsCompiled compile(String script, [String filepath = "<inline>"]) {
    _arguments[0].setString(script, this);
    _arguments[1].setString(filepath, this);
    return _action(JS_ACTION_COMPILE, 2, block: (results, length) {
      if (length == 2 &&
          results[0].isInt &&
          results[1].type == ARG_TYPE_RAW_POINTER) {
        int len = results[0].intValue;
        Pointer pointer = results[1].ptrValue;
        return IOJsCompiled(pointer, len);
      } else {
        throw Exception("Wrong result");
      }
    });
  }
  void loadCompiled(JsCompiled compiled) {
    if (compiled is IOJsCompiled) {
      _arguments[0].ptrValue = compiled.pointer;
      _arguments[0].type = ARG_TYPE_RAW_POINTER;
      _arguments[1].setInt(compiled.length);
      return _action(JS_ACTION_LOAD_COMPILED, 2);
    }
  }
}

const int _Int32Max = 2147483647;
const int _Int32Min = -2147483648;

extension JsArguemntExtension on JsArgument {

  void set(dynamic value, IOJsScript script) {
    if (value == null) {
      setNull();
    } else if (value is int) {
      setInt(value);
    } else if (value is double) {
      setDouble(value);
    } else if (value is bool) {
      setBool(value);
    } else if (value is String) {
      setString(value, script);
    } else if (value is IOJsValue) {
      setValue(value);
    } else if (value is Future) {
      setFuture(value, script);
    } else if (value is JsProxy) {
      setValue(value.value as IOJsValue);
    } else if (value is Map || value is List) {
      IOJsValue? val;
      reverse(script, () {
        JsValue obj = script.bind(value, classInfo: value is Map ? mapClass : listClass);
        val = script.collectionWrap(obj) as IOJsValue;
      });
      setValue(val!);
    } else if (value is Function) {
      IOJsValue? val;
      reverse(script, () {
        val = script.function((argv) => Function.apply(value, argv)) as IOJsValue;
      });
      setValue(val!);
    } else {
      IOJsValue? val;
      reverse(script, () {
        var info = script._classIndex[value.runtimeType]?.clazz;
        if (info == null) info = script._classList[0].clazz;
        val = script.bind(value, classInfo: info) as IOJsValue;
      });
      setValue(val!);
    }
  }

  void reverse(IOJsScript script, VoidCallback block) {
    Pointer backup = binder.backup(script._context);
    try {
      block();
    } finally {
      binder.reverse(script._context, backup);
    }
  }

  void setFuture(Future future, IOJsScript script) {
    type = ARG_TYPE_PROMISE;
    ptrValue = script._newPromise(future);
  }

  void setNull() {
    type = ARG_TYPE_NULL;
  }

  void setInt(int value) {
    type = value <= _Int32Max && value >= _Int32Min ? ARG_TYPE_INT32 : ARG_TYPE_INT64;
    intValue = value;
  }

  void setDouble(double value) {
    type = ARG_TYPE_DOUBLE;
    doubleValue = value;
  }

  void setBool(bool value) {
    type = ARG_TYPE_BOOL;
    intValue = value ? 1 : 0;
  }

  void setString(String value, IOJsScript script) {
    type = ARG_TYPE_STRING;
    var ptr = value.toNativeUtf8();
    ptrValue = ptr;
    script._temp.add(ptr);
  }

  void setValue(IOJsValue value) {
    type = ARG_TYPE_MANAGED_VALUE;
    ptrValue = value._ptr;
  }

  dynamic get(IOJsScript script) {
    switch (type) {
      case ARG_TYPE_INT32:
      case ARG_TYPE_INT64:
        return intValue;
      case ARG_TYPE_DOUBLE:
        return doubleValue;
      case ARG_TYPE_BOOL:
        return intValue != 0;
      case ARG_TYPE_STRING:
        return ptrValue.cast<Utf8>().toDartString();
      case ARG_TYPE_JS_STRING:
        var ptr = binder.toStringPtr(script._context, ptrValue);
        String ret = ptr.toDartString();
        binder.freeStringPtr(script._context, ptr);
        return ret;
      case ARG_TYPE_JS_VALUE:
        var ptr = binder.retainValue(script._context, ptrValue);
        if (ptr.ref.type == ARG_TYPE_MANAGED_VALUE) {
          return IOJsValue._js(script, ptr.ref.ptrValue);
        } else {
          return ptr.ref.get(script);
        }
      case ARG_TYPE_DART_CLASS: {
        var classInfo = script._classList[intValue];
        return IOJsValue._class(script, ptrValue, classInfo.clazz.type);
      }
      case ARG_TYPE_DART_OBJECT:
        return IOJsValue._instance(script, ptrValue, script._instances[ptrValue]);
    }
  }

  bool get isInt => type == ARG_TYPE_INT32 || type == ARG_TYPE_INT64;

}

JsScript scriptFactory({
  int maxArguments = MAX_ARGUMENTS,
  Function(String)? onUncaughtError,
  List<JsFileSystem> fileSystems = const []
}) => IOJsScript(
  maxArguments: maxArguments,
  onUncaughtError: onUncaughtError,
  fileSystems: fileSystems,
);