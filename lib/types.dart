
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'js_ffi.dart';

typedef CallFunction<T> = Function(T? self, List argv);

class JsFunction<T> {
  final bool isStatic;
  late CallFunction<T> function;

  /// New a static function
  JsFunction.sta(Function(List argv) func) :isStatic = true {
    function = (_, argv) => func(argv);
  }
  /// New a instance function
  JsFunction.ins(Function(T obj, List argv) func) : isStatic = false {
    function = (obj, argv) => func(obj!, argv);
  }
}

class JsField<T, V> {
  bool isStatic;
  final CallFunction<T>? getter;
  final CallFunction<T>? setter;

  /// New a static field
  JsField.sta({
    V Function()? get,
    Function(V)? set,
  }) : isStatic = true,
        assert(get != null || set != null),
        getter = (get == null ? null : (_, __) => get()),
        setter = (set == null ? null : (_, argv) => set(argv[0]));

  /// New a instance field
  JsField.ins({
    V Function(T)? get,
    Function(T, V)? set,
  }) : isStatic = false,
        assert(get != null || set != null),
        getter = (get == null ? null : (obj, __) => get(obj!)),
        setter = (set == null ? null : (obj, argv) => set(obj!, argv[0]));
}

const int MEMBER_FUNCTION     = 1 << 0;
const int MEMBER_CONSTRUCTOR  = 1 << 1;
const int MEMBER_GETTER       = 1 << 2;
const int MEMBER_SETTER       = 1 << 3;
const int MEMBER_STATIC       = 1 << 4;

class _MemberInfo<T> {
  String name;
  int type;
  CallFunction<T> func;

  _MemberInfo(this.name, this.type, this.func);

  dynamic call(T? obj, List argv) => func(obj, argv);
}

class ClassInfo<T> {
  final String name;
  final Type type;
  List<_MemberInfo<T>> members = [];

  ClassInfo({
    String? name,
    required T Function(List argv) newInstance,
    Map<String, JsFunction<T>> functions = const {},
    Map<String, JsField<T, dynamic>> fields = const {},
  }) : type = T, name = name == null ? T.toString() : name {
    members.add(_MemberInfo<T>(
        this.name,
        MEMBER_CONSTRUCTOR,
        (_, argv) => newInstance(argv)
    ));
    functions.forEach((name, func) {
      members.add(_MemberInfo<T>(
        name,
        MEMBER_FUNCTION | (func.isStatic ? MEMBER_STATIC : 0),
        func.function
      ));
    });
    fields.forEach((name, field) {
      if (field.getter != null) {
        members.add(_MemberInfo<T>(
            name,
            MEMBER_GETTER | (field.isStatic ? MEMBER_STATIC : 0),
            field.getter!
        ));
      }
      if (field.setter != null) {
        members.add(_MemberInfo<T>(
            name,
            MEMBER_SETTER | (field.isStatic ? MEMBER_STATIC : 0),
            field.setter!
        ));
      }
    });
    if (!functions.containsKey("toString")) {
      members.add(_MemberInfo<T>(
          "toString",
          MEMBER_FUNCTION,
              (self, argv) => self.toString()
      ));
    }
  }

  Pointer<JsClass> createJsClass() {
    Pointer<JsClass> jsClass = malloc.allocate(sizeOf<JsClass>());
    jsClass.ref.name = name.toNativeUtf8();
    int len = members.length;
    jsClass.ref.membersLength = len;
    jsClass.ref.members = malloc.allocate(len * sizeOf<JsMember>());
    for (int i = 0; i < len; ++i) {
      var member = jsClass.ref.members[i];
      var memberInfo = members[i];
      member.name = memberInfo.name.toNativeUtf8();
      member.type = memberInfo.type;
    }
    return jsClass;
  }

  void deleteJsClass(Pointer<JsClass> jsClass) {
    malloc.free(jsClass.ref.name);
    for (int i = 0, t = jsClass.ref.membersLength; i < t; ++i) {
      var member = jsClass.ref.members[i];
      malloc.free(member.name);
    }
    malloc.free(jsClass.ref.members);
    malloc.free(jsClass);
  }
}

abstract class JsDispose {
  void dispose();
}



const int MAX_ARGUMENTS = 16;

const int JS_ACTION_EVAL = 1;
const int JS_ACTION_TO_STRING = 2;
const int JS_ACTION_SET = 3;
const int JS_ACTION_GET = 4;
const int JS_ACTION_INVOKE = 5;
const int JS_ACTION_BIND = 6;
const int JS_ACTION_PROMISE_COMPLETE = 7;
const int JS_ACTION_WRAP_FUNCTION = 8;
const int JS_ACTION_CALL = 9;
const int JS_ACTION_RUN = 10;
const int JS_ACTION_RUN_PROMISE = 11;

const int JS_ACTION_IS_ARRAY = 100;
const int JS_ACTION_IS_FUNCTION = 101;
const int JS_ACTION_IS_CONSTRUCTOR = 102;

const int DART_ACTION_CONSTRUCTOR = 1;
const int DART_ACTION_CALL = 2;
const int DART_ACTION_DELETE = 3;
const int DART_ACTION_CALL_FUNCTION = 4;
const int DART_ACTION_MODULE_NAME = 5;
const int DART_ACTION_LOAD_MODULE = 6;

const int ARG_TYPE_NULL = 0;
const int ARG_TYPE_INT32 = 1;
const int ARG_TYPE_INT64 = 2;
const int ARG_TYPE_DOUBLE = 3;
const int ARG_TYPE_BOOL = 4;
const int ARG_TYPE_STRING = 5;
const int ARG_TYPE_JS_STRING = 6;
const int ARG_TYPE_JS_VALUE = 7;
const int ARG_TYPE_DART_CLASS = 8;
const int ARG_TYPE_DART_OBJECT = 9;
const int ARG_TYPE_RAW_POINTER = 10;
const int ARG_TYPE_PROMISE = 11;
const int ARG_TYPE_MANAGED_VALUE = 12;