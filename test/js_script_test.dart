import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:js_script/js_script.dart';

void main() {
  const MethodChannel channel = MethodChannel('js_script');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    JsScript script = JsScript();
    expect(script.eval("5 + 8"), 13);
    expect(script.eval("'hello'"), "hello");

    script.dispose();
  });
}
