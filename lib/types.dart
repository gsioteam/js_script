
import 'package:js_script/js_script.dart';

typedef CallFunction<T> = Function(T? self, List argv);

class JsFunction<T> {
  final bool isStatic;
  late CallFunction<dynamic> function;

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
  final CallFunction<dynamic>? getter;
  final CallFunction<dynamic>? setter;

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
  CallFunction<dynamic> func;

  _MemberInfo(this.name, this.type, this.func);

  dynamic call(dynamic obj, List argv) => func(obj, argv);
}

class ClassInfo<T> {
  final String name;
  final Type type;
  List<_MemberInfo<T>> members = [];

  ClassInfo({
    String? name,
    required T Function(JsScript, List argv) newInstance,
    Map<String, JsFunction<T>> functions = const {},
    Map<String, JsField<T, dynamic>> fields = const {},
  }) : type = T, name = name == null ? T.toString() : name {
    members.add(_MemberInfo<T>(
        this.name,
        MEMBER_CONSTRUCTOR,
        (script, argv) => newInstance(script, argv)
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

}

abstract class JsDispose {
  void dispose();
}



const int MAX_ARGUMENTS = 16;
