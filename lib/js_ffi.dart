
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'types.dart';

typedef SetupJsContextFunc = Pointer Function(Pointer<JsArgument>, Pointer<JsArgument>, Pointer<JsHandlers>);
typedef DeleteJsContextFunc = Void Function(Pointer);
typedef JsContextActionFunc = Int32 Function(Pointer context, Int32 type, Int32 argc);
typedef JsContextToStringFunc = Pointer<Utf8> Function(Pointer context, Pointer ptr);
typedef JsContextFreeStringFunc = Void Function(Pointer context, Pointer);
typedef JsContextRetainValueFunc = Pointer<JsArgument> Function(Pointer context, Pointer);
typedef JsContextReleaseValueFunc = Void Function(Pointer context, Pointer);
typedef JsContextClearCacheFunc = Void Function(Pointer context);
typedef JsContextRegisterClassFunc = Pointer Function(Pointer context, Pointer<JsClass> jsClass, Int32 id);
typedef JsContextHasPendingJobFunc = Int32 Function(Pointer context);
typedef JsContextExecutePendingJobFunc = Int32 Function(Pointer context);
typedef JsContextNewPromiseFunc = Pointer Function(Pointer context);

typedef JsPrintHandlerFunc = Void Function(Int32 type, Pointer<Utf8> str);
typedef JsToDartActionFunc = Int32 Function(Pointer context, Int32 type, Int32 argc);

class JsHandlers extends Struct {
  @Int32()
  int? maxArguments;

  Pointer<NativeFunction<JsPrintHandlerFunc>>? print;
  Pointer<NativeFunction<JsToDartActionFunc>>? toDartAction;
}

class JsArgument extends Struct {
  @Int16()
  external int type;

  @Int64()
  external int intValue;

  @Double()
  external double doubleValue;

  external Pointer ptrValue;
}

class JsMember extends Struct {
  external Pointer<Utf8> name;

  @Uint32()
  external int type;
}

class JsClass extends Struct {
  external Pointer<Utf8> name;

  @Int32()
  external int membersLength;

  external Pointer<JsMember> members;
}

class JsBinder {
  final DynamicLibrary nativeGLib = Platform.isAndroid
      ? DynamicLibrary.open("libqjs.so") :
  (Platform.isLinux || Platform.isWindows ?
      DynamicLibrary.open(Platform.isWindows ?
      "libjs_script_plugin.dll" : "libjs_script_plugin.so")
          : DynamicLibrary.process());

  late SetupJsContextFunc setupJsContext;
  late void Function(Pointer) deleteJsContext;
  late int Function(Pointer context, int type, int argc) action;
  late JsContextToStringFunc toStringPtr;
  late void Function(Pointer, Pointer) freeStringPtr;
  late JsContextRetainValueFunc retainValue;
  late void Function(Pointer context, Pointer) releaseValue;
  late void Function(Pointer context) clearCache;
  late Pointer Function(Pointer, Pointer<JsClass>, int) registerClass;
  late JsContextNewPromiseFunc newPromise;
  late int Function(Pointer) hasPendingJob;
  late int Function(Pointer) executePendingJob;

  JsBinder() {
    print(Platform.isMacOS);
    setupJsContext = nativeGLib
        .lookup<NativeFunction<SetupJsContextFunc>>("setupJsContext").asFunction();
    deleteJsContext = nativeGLib
        .lookup<NativeFunction<DeleteJsContextFunc>>("deleteJsContext").asFunction();
    action = nativeGLib
        .lookup<NativeFunction<JsContextActionFunc>>("jsContextAction").asFunction();
    toStringPtr = nativeGLib
        .lookup<NativeFunction<JsContextToStringFunc>>("jsContextToStringPtr").asFunction();
    freeStringPtr = nativeGLib
        .lookup<NativeFunction<JsContextFreeStringFunc>>("jsContextFreeStringPtr").asFunction();
    retainValue = nativeGLib
        .lookup<NativeFunction<JsContextRetainValueFunc>>("jsContextRetainValue").asFunction();
    releaseValue = nativeGLib
        .lookup<NativeFunction<JsContextReleaseValueFunc>>("jsContextReleaseValue").asFunction();
    clearCache = nativeGLib
        .lookup<NativeFunction<JsContextClearCacheFunc>>("jsContextClearCache").asFunction();
    registerClass = nativeGLib
        .lookup<NativeFunction<JsContextRegisterClassFunc>>("jsContextRegisterClass").asFunction();
    newPromise = nativeGLib
        .lookup<NativeFunction<JsContextNewPromiseFunc>>("jsContextNewPromise").asFunction();
    hasPendingJob = nativeGLib
        .lookup<NativeFunction<JsContextHasPendingJobFunc>>("jsContextHasPendingJob").asFunction();
    executePendingJob = nativeGLib
        .lookup<NativeFunction<JsContextExecutePendingJobFunc>>("jsContextExecutePendingJob").asFunction();
  }
}

var binder = JsBinder();

extension FfiClassInfo<T> on ClassInfo<T> {
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
const int JS_ACTION_PROPERTY_NAMES = 12;
const int JS_ACTION_NEW_OBJECT = 13;

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