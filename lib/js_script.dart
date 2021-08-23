
import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

import 'types.dart';
export 'types.dart';

import 'factory_stub.dart'
if (dart.library.io) 'js_script_io.dart'
if (dart.library.html) 'js_script_web.dart';

enum JsValueType {
  JsObject,
  DartInstance,
  DartClass
}

abstract class JsFileSystem {
  final String? mount;
  JsFileSystem([String? mount]) :
        mount = mount != null ? (mount[0] != '/' ? "/$mount" : mount) : null;

  bool exist(String filename);
  String? read(String filename);
}

extension JsFileSystemList on List<JsFileSystem> {
  String? findPath(String basename, String module) {
    if (isEmpty) return null;
    String filepath;
    if (module[0] == "/") {
      filepath = module;
    } else {
      filepath = path.join(basename, '..', module);
    }
    if (filepath[0] != "/") filepath = "/" + filepath;
    filepath = path.normalize(filepath);
    String ext = path.extension(filepath);

    if (ext.isEmpty) {
      for (var fileSystem in this) {
        if (fileSystem.mount != null) {
          String mountPath = "${fileSystem.mount!}/";
          if (filepath.startsWith(mountPath)) {
            filepath = filepath.replaceFirst(fileSystem.mount!, "");
          } else {
            continue;
          }
        }
        String? testFile(String filepath) {
          String newPath = "$filepath.js";
          if (fileSystem.exist(newPath)) return newPath;
          newPath = "$filepath.json";
          if (fileSystem.exist(newPath)) return newPath;
          newPath = "$filepath/package.json";
          if (fileSystem.exist(newPath)) {
            var code = fileSystem.read(newPath);
            var json = jsonDecode(code!);
            if (json is Map) {
              var main = json["main"];
              if (main != null) {
                return "$filepath/$main";
              }
            }
          }
          return null;
        }

        String? newPath = testFile(filepath);
        if (newPath != null)
          return newPath;

        String basename = path.dirname(filepath);
        while (true) {
          if (basename.isEmpty) break;
          String modulePath = path.join(basename, 'node_modules', module);
          var newPath = testFile(modulePath);
          if (newPath != null) return newPath;
          basename = path.dirname(basename);
        }

      }
    } else {
      for (var fileSystem in this) {
        if (fileSystem.exist(filepath)) return filepath;
      }
    }
  }

  String? loadCode(String path) {
    if (isEmpty) return null;
    for (var fileSystem in this) {
      var code = fileSystem.read(path);
      if (code != null) return code;
    }
    return null;
  }
}

abstract class JsValue {

  bool _disposed = false;
  int _retainCount = 0;
  JsScript get script;
  final dynamic dartObject;
  final JsValueType type;

  @protected
  JsValue({
    required this.dartObject,
    required this.type,
  });

  void _dispose();

  // retain count +1
  int retain() => ++_retainCount;

  // retain count -1 when retain count <= 0 dispose this object.
  int release() {
    if (--_retainCount <= 0) {
      if (!_disposed)
        _dispose();
    }
    return _retainCount;
  }

  // release this after 30ms.
  void delayRelease() {
    Future.delayed(Duration(milliseconds: 30), () {
      release();
    });
  }

  /// Set property to this JS object.
  ///
  /// The [key] would be a String or int value
  ///
  /// The [value] could be one of [int], [double], [bool],
  /// [String], [Future] and [JsValue]
  void set(dynamic key, dynamic value);

  /// Get a property of this JS object.
  ///
  /// The result could be one of [int], [double], [bool],
  /// [String] and [JsValue]
  dynamic get(dynamic key);

  operator[]= (dynamic key, dynamic value) => set(key, value);
  operator[] (dynamic key) => get(key);

  /// Invoke a property function.
  dynamic invoke(String name, [List argv = const [],]);

  /// Call as a JS function object.
  dynamic call([List argv = const []]);

  bool get isArray;

  bool get isFunction;

  bool get isConstructor;

  Future get asFuture;

  List<String> getOwnPropertyNames();

  @override
  String toString();
}

abstract class JsScript {
  final List<JsFileSystem> fileSystems;

  JsScript.init({required this.fileSystems});

  factory JsScript({
    int maxArguments = MAX_ARGUMENTS,
    Function(String)? onUncaughtError,
    List<JsFileSystem> fileSystems = const []
  }) => scriptFactory(
    maxArguments: maxArguments,
    onUncaughtError: onUncaughtError,
    fileSystems: fileSystems
  );

  /// Define a bound class in the JS context.
  void addClass(ClassInfo clazz);

  /// Shutdown this JS context.
  void dispose();

  eval(String script, [String filepath = "<inline>"]);

  /// Run a JS script which would be find from [fileSystems], and
  /// the script would be treat as a module.
  ///
  /// The result is the default module exports.
  run(String filepath);

  /// Establish a binding relationship between dart and js object
  JsValue bind(dynamic object, {
    ClassInfo? classInfo,
    JsValue? classFunc
  });

  /// Send a dart callback to JS context.
  JsValue function(Function(List argv) func);

  JsValue newObject();

  JsValue get global;
}
