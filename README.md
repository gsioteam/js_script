# js_script

Run JS script.

## Usage

```dart
// Create a JS context.
JsScript script = JsScript();
// Define a class.
var classInfo = ClassInfo<TestClass>(
    newInstance: (_) => TestClass(),
    fields: {
        "field": JsField.ins(
            get: (obj) => obj.field,
            set: (obj, val) => obj.field=val,
        ),
    },
    functions: {
        "method": JsFunction.ins((obj, argv) => obj.method()),
        "wait": JsFunction.ins((obj, argv) => obj.wait(argv[0])),
    }
);
// Send the class info to JS context.
script.addClass(classInfo);

// Have some test.
script.eval("var obj = new TestClass()");
test("[JS] obj.field == 1", script.eval("obj.field") == 1);
test("[JS] obj.method() == 3", script.eval("obj.method()") == 3);

JsValue jsValue = script.eval("obj");
script.eval("obj.field = 3;");
test("[Dart] obj.field == 3", jsValue.dartObject.field == 3);
test("[Dart] obj.method() == 9", jsValue.dartObject.method() == 9);

{
    // Send a dart object to JS context.
    TestClass obj2 = TestClass();
    obj2.field = 4;
    JsValue jsValue = script.bind(obj2, classInfo: classInfo);
    test("[JS] obj2.field == 4", jsValue["field"] == 4);
}

{
    // Send a dart function to JS context.
    JsValue func = script.function((argv) => "hello" + argv[0]);
    test("[JS] call function", func.call(["world"]) == "helloworld");
}

{
    // Using the Future as Promise in JS.
    // And using the Promise as a Future.
    JsValue jsPromise = script.eval("""
    new Promise(async function(resolve, reject) {
        await obj.wait(3);
        resolve("over");
    });
    """);
    jsPromise.retain();
    var time = DateTime.now();
    var res = await jsPromise.asFuture;
    jsPromise.release();
    test("[JS] wait for ${DateTime.now().difference(time).inMilliseconds}ms", res == "over");
}
```

### FileSystem

```dart
JsScript script = JsScript(
    fileSystems: [
        // Add a asar file.
        AsarFileSystem(await data),
        // Add memory files.
        MemoryFileSystem({
            "/test.js": """
            const md5 = require('md5');
            module.exports = md5('hello');
            """
        })
    ]
);
var ret = script.run("test.js");
```

For supporting npm pack, you can import it via a [asar file](https://github.com/electron/asar).
