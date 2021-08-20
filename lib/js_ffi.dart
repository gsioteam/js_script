
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

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

typedef JsPrintHandlerFunc = Void Function(Int32 type, Pointer<Utf8> str);
typedef JsToDartActionFunc = Int32 Function(Pointer context, Int32 type, Int32 argc);
typedef JsContextNewPromiseFunc = Pointer Function(Pointer context);

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
      ? DynamicLibrary.open("libqjs.so")
      : DynamicLibrary.process();

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

