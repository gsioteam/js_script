import 'package:js_script/js_script.dart';
import 'package:js_script/types.dart';

ClassInfo<Map> mapClass = ClassInfo<Map>(
    name: "DartMap",
    newInstance: (_,__) => {},
    functions: {
      "set": JsFunction.ins((obj, argv) => obj[argv[0]] = argv[1]),
      "get": JsFunction.ins((obj, argv) => obj[argv[0]]),
    },
    fields: {
      "length": JsField.ins(
        get: (obj) => obj.length,
      )
    }
);

ClassInfo<List> listClass = ClassInfo<List>(
    name: "DartList",
    newInstance: (_,__) => [],
    functions: {
      "set": JsFunction.ins((obj, argv) => obj[argv[0]] = argv[1]),
      "get": JsFunction.ins((obj, argv) => obj[argv[0]]),
    },
    fields: {
      "length": JsField.ins(
          get: (obj) => obj.length,
          set: (obj, argv) => obj.length = argv[0]
      )
    }
);
