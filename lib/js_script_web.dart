
import 'dart:async';
import 'dart:js' as js;

import 'common.dart';
import 'js_script.dart';

wrap(dynamic value, WebJsScript script) {
  if (value is js.JsObject) {
    if (value[script.privateKey] != null) {
      return WebJsValue(script, value,
          type: JsValueType.DartInstance,
          dartObject: value[script.privateKey]
      );
    } else if (value[script.classPrivateKey] != null) {
      return WebJsValue(script, value,
          type: JsValueType.DartClass,
          dartObject: value[script.classPrivateKey].type
      );
    }
    return WebJsValue(script, value);
  } else {
    return value;
  }
}

jsValue(dynamic value, WebJsScript script) {
  if (value is Future) {
    js.JsObject handler = js.JsObject.jsify({});
    value.then((value) => handler.callMethod("resolve", [jsValue(value, script)]));
    value.catchError((error) => handler.callMethod("reject", [jsValue(error, script)]));
    return script.newPromise(handler);
  } else if (value is WebJsValue) {
    return value._object;
  } else if (value is Function) {
    WebJsValue func = script.function((argv) => Function.apply(value, argv)) as WebJsValue;
    return func._object;
  } else if (value is Map || value is List) {
    WebJsValue obj = script.bind(value, classInfo: value is Map ? mapClass : listClass) as WebJsValue;
    obj = script.collectionWrap(obj) as WebJsValue;
    return obj._object;
  } else {
    return value;
  }
}

class WebJsValue extends JsValue {
  js.JsObject _object;

  WebJsScript script;

  WebJsValue(this.script, this._object, {
    dynamic dartObject,
    JsValueType type = JsValueType.JsObject,
  }) : super(
      dartObject: dartObject,
      type: type
  );

  void set(dynamic key, dynamic value) => _object[key] = jsValue(value, script);
  dynamic get(dynamic key) => wrap(_object[key], script);

  dynamic invoke(String name, [List argv = const [],]) {
    _object.callMethod(name, argv);
  }

  dynamic call([List argv = const []]) =>
      wrap((_object as js.JsFunction).apply(argv.map((e) => jsValue(e, script)).toList()), script);

  bool get isArray => _object is js.JsArray;
  bool get isFunction => _object is js.JsFunction;
  bool get isConstructor => _object is js.JsFunction;

  Future get asFuture {
    Completer completer = Completer();
    js.JsObject promise = script.resolve.apply([_object]);
    promise.callMethod("then", [js.JsFunction.withThis((self, value) {
      completer.complete(wrap(value, script));
    })]);
    promise.callMethod("catch", [js.JsFunction.withThis((self, error) {
      completer.completeError(wrap(error, script));
    })]);
    return completer.future;
  }

  List<String> getOwnPropertyNames() {
    js.JsArray arr = script.getPropertyNames.apply([_object]);
    return arr.toList().cast<String>();
  }

  String toString() => _object.toString();

  @override
  void delayRelease() {
  }

  @override
  void onDispose() {
  }

  @override
  int release() => 1;

  @override
  int retain() => 1;
}

class _WebField {
  int getter = 0;
  int setter = 0;
  bool isStatic = false;
}

class WebJsScript extends JsScript {
  late js.JsFunction _eval;
  WebJsScript({fileSystems = const []}) : super.init(fileSystems: fileSystems) {
    _eval = js.context["eval"];
    addClass(ClassInfo<Object>(
      name: "DartObject",
      newInstance: (_, argv) => Object(),
    ));
    addClass(mapClass);
    addClass(listClass);
  }

  static js.JsFunction? _resolve;
  js.JsFunction get resolve {
    if (_resolve == null) {
      _resolve = _eval.apply(["((obj) => Promise.resolve(obj))"]) as js.JsFunction;
    }
    return _resolve!;
  }

  static js.JsFunction? _getPropertyNames;
  js.JsFunction get getPropertyNames {
    if (_getPropertyNames == null) {
      _getPropertyNames = _eval.apply(["((obj) => Object.getOwnPropertyNames(obj))"]) as js.JsFunction;
    }
    return _getPropertyNames!;
  }

  js.JsFunction? _callFunction;
  js.JsFunction get callFunction {
    if (_callFunction == null) {
      _callFunction = js.JsFunction.withThis((js.JsObject self, ClassInfo classInfo, int method, List args) {
        var member = classInfo.members[method];
        List arr = [];
        var iter = args.iterator;
        while (true) {
          try {
            if (iter.moveNext()) {
              arr.add(wrap(iter.current, this));
            } else {
              break;
            }
          } catch (e) {
            arr.add(null);
            break;
          }
        }
        var ret;
        if (method == 0) {
          ret = member.call(this, arr);
        } else if (member.type & MEMBER_STATIC != 0) {
          ret = member.call(null, arr);
        } else {
          ret = member.call(self[privateKey], arr);
        }
        return jsValue(ret, this);
      });
    }
    return _callFunction!;
  }

  final String privateKey = '_\$private';
  final String classPrivateKey = '_\$classPrivate';

  Map<ClassInfo, js.JsFunction> classes = {};

  @override
  void addClass(ClassInfo classInfo) {
    List<String> arr = ["(function(privateKey, call, classInfo) { \nfunction ${classInfo.name}() {"];
    arr.add("if (arguments[0] != privateKey) this[privateKey] = call.apply(this, [classInfo, 0, Array.prototype.slice.call(arguments)])");
    arr.add("};");

    Map<String, _WebField> fields = {};
    for (int i = 1, t = classInfo.members.length; i < t; ++i) {
      var member = classInfo.members[i];
      if (member.type & MEMBER_FUNCTION != 0) {
        arr.add("""
${classInfo.name}${member.type & MEMBER_STATIC == 0 ? '.prototype' : ''}.${member.name} = function() {
  return call.apply(this, [classInfo, $i, Array.prototype.slice.call(arguments)]);
};
        """);
      } else {
        _WebField field = fields.containsKey(member.name)
            ? fields[member.name]!
            : (fields[member.name] = new _WebField());
        if (member.type & MEMBER_GETTER != 0) {
          field.getter = i;
        } else if (member.type & MEMBER_SETTER != 0) {
          field.setter = i;
        }
        field.isStatic = member.type & MEMBER_STATIC != 0;
      }
    }
    for (var iter in fields.entries) {
      String name = iter.key;
      var field = iter.value;
      arr.add('Object.defineProperty(${classInfo.name}${field.isStatic ? '' : '.prototype'}, "$name", {');
      if (field.getter != 0) {
        arr.add("""
  get: function() {
    return call.apply(this, [classInfo, ${field.getter}, Array.prototype.slice.call(arguments)])
  },
        """);

      }
      if (field.setter != 0) {
        arr.add("""
  set: function() {
    return call.apply(this, [classInfo, ${field.setter}, Array.prototype.slice.call(arguments)])
  }
        """);
      }
      arr.add('});');
    }
    arr.add("return ${classInfo.name}});");
    js.JsFunction func = _eval.apply([arr.join('\n')]);
    js.JsFunction clazz = func.apply([privateKey, callFunction, classInfo]);
    clazz[classPrivateKey] = classInfo;
    global[classInfo.name] = clazz;
    classes[classInfo] = clazz;
  }

  @override
  JsValue bind(object, {ClassInfo? classInfo, JsValue? classFunc}) {
    js.JsFunction constructor;
    if (classInfo != null) {
      if (!classes.containsKey(classInfo)) {
        addClass(classInfo);
      }
      constructor = classes[classInfo]!;
    } else {
      constructor = (classFunc as WebJsValue)._object as js.JsFunction;
    }
    js.JsObject obj = js.JsObject(constructor, [privateKey]);
    obj[privateKey] = object;
    return wrap(obj, this);
  }

  @override
  void dispose() {
  }

  js.JsFunction? _newPromise;
  js.JsObject newPromise(js.JsObject handler) {
    if (_newPromise == null) {
      _newPromise = _eval.apply(["""
      (function(handler) {
        return new Promise(function(resolve, reject) {
          handler.resolve = resolve;
          handler.reject = reject;
        });
      })
      """]);
    }
    return _newPromise!.apply([handler]);
  }

  Map<String, dynamic> _requireCache = {};

  dynamic runModule(String code, String filepath) {
    js.JsFunction func = _eval.apply([['(function (require, module) {', code, '})'].join('\n')]);
    js.JsFunction require = js.JsFunction.withThis((_, filename) {
      return loadModule(filepath, filename);
    });
    js.JsObject module = js.JsObject.jsify({'exports': {}});
    func.apply([require, module]);
    return module["exports"];
  }

  dynamic loadModule(String filepath, String filename) {
    String? path = fileSystems.findPath(filepath, filename);
    if (path != null) {
      if (_requireCache.containsKey(path)) {
        return _requireCache[path];
      } else {
        String? code = fileSystems.loadCode(path);
        if (code != null) {
          return _requireCache[path] = runModule(code, path);
        }
      }
    }
    return js.JsObject.jsify({});
  }

  @override
  eval(String script, [String filepath = "<inline>"]) {
    js.JsFunction require = js.JsFunction.withThis((_, filename) {
      return loadModule(filepath, filename);
    });
    js.context['require'] = require;
    var ret = wrap(_eval.apply([script]), this);
    // (global as WebJsValue)._object.deleteProperty('require');
    return ret;
  }

  @override
  JsValue function(Function(List argv) func) =>
      wrap(js.JsFunction.withThis((self, [arg1, arg2, arg3, arg4, arg5]) {
        List argv;
        if (arg5 != null) {
          argv = [arg1, arg2, arg3, arg4, arg5];
        } else if (arg4 != null) {
          argv = [arg1, arg2, arg3, arg4];
        } else if (arg3 != null) {
          argv = [arg1, arg2, arg3];
        } else if (arg2 != null) {
          argv = [arg1, arg2];
        } else if (arg1 != null) {
          argv = [arg1];
        } else {
          argv = [];
        }
        return jsValue(func(argv.map((e) => wrap(e, this)).toList()), this);
      }), this);

  @override
  JsValue newObject() => WebJsValue(this, js.JsObject.jsify({}));

  @override
  run(String filepath) {
    String? path = fileSystems.findPath("/", filepath);
    if (path != null) {
      String? code = fileSystems.loadCode(path);
      if (code != null) {
        return wrap(runModule(code, path), this);
      }
    }
  }

  JsValue? _global;
  JsValue get global {
    if (_global == null) {
      _global = WebJsValue(this, js.context);
      _global!.retain();
    }
    return _global!;
  }

  JsValue? _wrapper;
  JsValue collectionWrap(JsValue value) {
    if (_wrapper == null) {
      _wrapper = eval("""
(function() {
    const handler = {
        get: function(obj, prop) {
            if (prop == 'length')
                return obj.length;
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
    }
    return _wrapper!.call([value]);
  }

  @override
  JsBuffer newBuffer(int length) {
    throw UnimplementedError();
  }
  JsCompiled compile(String script, [String filepath = "<inline>"]) {
    throw Exception("NotImplemented");
  }
  void loadCompiled(JsCompiled compiled) {
    throw Exception("NotImplemented");
  }
}

class JsScriptPlugin {
  static void registerWith(registrar) {}
}

JsScript scriptFactory({
  int maxArguments = MAX_ARGUMENTS,
  Function(String)? onUncaughtError,
  List<JsFileSystem> fileSystems = const []
}) {
  return WebJsScript(fileSystems: fileSystems);
}