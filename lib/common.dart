import 'package:js_script/js_script.dart';
import 'package:js_script/types.dart';

dynamic dartToJsValue(JsScript script, dynamic data, [Map? cache]) {
  if (cache == null) cache = {};
  var ret = cache[data];
  if (ret != null) return ret;
  if (data is Map) {
    JsValue value = script.newObject();
    cache[data] = value;
    for (var key in data.keys) {
      value[key] = dartToJsValue(script, data[key], cache);
    }
    return value;
  } else if (data is List) {
    JsValue value = script.newArray();
    cache[data] = value;
    for (int i = 0, t = data.length; i < t; ++i) {
      value[i] = dartToJsValue(script, data[i], cache);
    }
    return value;
  } else {
    return data;
  }
}

ClassInfo<Map> mapClass = ClassInfo<Map>(
    name: "DartMap",
    newInstance: (_,__) => {},
    functions: {
      "set": JsFunction.ins((obj, argv) => obj[argv[0]] = argv[1]),
      "get": JsFunction.ins((obj, argv) => obj[argv[0]]),
      "toJSON": JsFunction.ins((obj, argv) => dartToJsValue((argv[0] as JsValue).script, obj)),
    },
    fields: {
      "length": JsField.ins(
        get: (obj) => obj.length,
      )
    }
);

int _toIndex(data) {
  if (data is String) {
    return int.parse(data);
  } else {
    return data;
  }
}

ClassInfo<List> listClass = ClassInfo<List>(
    name: "DartList",
    newInstance: (_,__) => [],
    functions: {
      "set": JsFunction.ins((obj, argv) => obj[_toIndex(argv[0])] = argv[1]),
      "get": JsFunction.ins((obj, argv) => obj[_toIndex(argv[0])]),
      "toJSON": JsFunction.ins((obj, argv) => dartToJsValue((argv[0] as JsValue).script, obj)),
    },
    fields: {
      "length": JsField.ins(
          get: (obj) => obj.length,
          set: (obj, argv) => obj.length = argv[0]
      )
    }
);
