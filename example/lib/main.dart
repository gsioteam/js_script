import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:js_script/filesystems.dart';
import 'package:js_script/js_script.dart';
import 'package:js_script/types.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class TestClass {
  int field = 1;

  int method() => field * 3;
  Future<void> wait(int sec) => Future.delayed(Duration(seconds: sec));
}

class _MyAppState extends State<MyApp> {

  late List<Widget> children = [];
  late Future<ByteData> data;

  @override
  void initState() {
    super.initState();
    data = rootBundle.load("res/npmpack.asar");
  }

  dispose() {
    super.dispose();
  }

  void addLine(String str) {
    print(str);
    setState(() {
      children.add(Text(str, style: TextStyle(color: Colors.black),));
    });
  }

  void test(String str, bool test) {
    addLine("$str ===> ${test ? "OK" : "Error"}");
  }

  void run() async {
    JsScript script = JsScript(
      fileSystems: [
        AsarFileSystem(await data),
        MemoryFileSystem({
          "/test.js": """
          const md5 = require('md5');
          module.exports = md5('hello');
          """
        })
      ]
    );

    test("1 + 2 = 3", script.eval("1 + 2") == 3);

    var classInfo = ClassInfo<TestClass>(
      newInstance: (_, __) => TestClass(),
      fields: {
        "field": JsField.ins(
          get: (obj) => obj.field,
          set: (obj, val) => obj.field=val,
        ),
      },
      functions: {
        "method": JsFunction.ins((obj, argv) => obj.method()),
        "method2": JsFunction.sta((argv) => 3),
        "wait": JsFunction.ins((obj, argv) => obj.wait(argv[0])),
      }
    );
    script.addClass(classInfo);

    script.eval("var obj = new TestClass()");
    test("[JS] obj.field == 1", script.eval("obj.field") == 1);
    test("[JS] obj.method() == 3", script.eval("obj.method()") == 3);

    JsValue jsValue = script.eval("obj");
    script.eval("obj.field = 3;");
    test("[Dart] obj.field == 3", jsValue.dartObject.field == 3);
    test("[Dart] obj.method() == 9", jsValue.dartObject.method() == 9);

    {
      //Test bind
      TestClass obj2 = TestClass();
      obj2.field = 4;
      JsValue jsValue = script.bind(obj2, classInfo: classInfo);
      test("[JS] obj2.field == 4", jsValue["field"] == 4);
    }

    {
      //Test function
      JsValue func = script.function((argv) => "hello" + argv[0]);
      var obj = func.call(["world"]);
      print(obj);
      test("[JS] call function", func.call(["world"]) == "helloworld");
    }

    {
      JsValue jsPromise = script.eval("""
      new Promise(async function(resolve, reject) {
        await obj.wait(3);
        resolve("over");
      });
      """);
      var time = DateTime.now();
      var res = await jsPromise.asFuture;
      test("[JS] wait for ${DateTime.now().difference(time).inMilliseconds}ms", res == "over");
    }

    {
      JsValue main = script.eval("""
      (function () {
        let ret = 0;
        for (let i = 0; i < 1000000; ++i) {
          ret += obj.method();
        }
        return ret;
      });
      """);

      var time = DateTime.now();
      var res = main.call();
      test("[JS] call dart method 1000000 times, using ${DateTime.now().difference(time).inMilliseconds}ms", res == 9000000);

    }

    {
      var ret = script.eval("""
      const md5 = require('md5');
      md5('hello');
      """);
      test("[JS] require md5", ret == '5d41402abc4b2a76b9719d911017c592');
      ret = script.run("test.js");
      test("[JS] run file in FileSystem", ret == '5d41402abc4b2a76b9719d911017c592');
    }
    {
      JsValue func = script.eval("""
      (function (func, map) {
        return func(map["test"])
      })
      """);
      test("[JS] test auto convert ", func.call([(content) {
        return content;
      }, {"test": 26}]) == 26);
    }

    script.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: ListView.builder(
          itemBuilder: (context, index) {
            return children[index];
          },
          itemCount: children.length,
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: run,
          child: Icon(Icons.run_circle_outlined),
        ),
      ),
    );
  }
}
