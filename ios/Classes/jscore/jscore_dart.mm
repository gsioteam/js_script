//
//  jscore_dart.cpp
//  js_script
//
//  Created by gen on 8/19/21.
//

#include <stdio.h>
#include <vector>
#include <map>
#include <string>
#include <set>
#import <JavaScriptCore/JavaScriptCore.h>


const int JS_ACTION_EVAL = 1;
const int JS_ACTION_TO_STRING = 2;
const int JS_ACTION_SET = 3;
const int JS_ACTION_GET = 4;
const int JS_ACTION_INVOKE = 5;
const int JS_ACTION_BIND = 6;
const int JS_ACTION_PROMISE_COMPLETE = 7;
const int JS_ACTION_WRAP_FUNCTION = 8;
const int JS_ACTION_CALL = 9;

const int DART_ACTION_CONSTRUCTOR = 1;
const int DART_ACTION_CALL = 2;
const int DART_ACTION_DELETE = 3;
const int DART_ACTION_CALL_FUNCTION = 4;

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

const int MEMBER_FUNCTION     = 1 << 0;
const int MEMBER_CONSTRUCTOR  = 1 << 1;
const int MEMBER_GETTER       = 1 << 2;
const int MEMBER_SETTER       = 1 << 3;
const int MEMBER_STATIC       = 1 << 4;


const int _Int32Max = 2147483647;
const int _Int32Min = -2147483648;

class JsContext;

typedef void(*JsPrintHandler)(int type, const char *str);
typedef int(*JsToDartActionHandler)(JsContext *, int type, int argc);

struct JsHandlers {
    int maxArguments;
    JsPrintHandler print;
    JsToDartActionHandler toDartAction;
};

struct JsArgument {
    short type;
    int64_t intValue;
    double_t doubleValue;
    void *ptrValue;

    void setNull() {
        type = ARG_TYPE_NULL;
    }

    void set(int value) {
        type = ARG_TYPE_INT32;
        intValue = value;
    }
    void set(int64_t value) {
        type = ARG_TYPE_INT64;
        intValue = value;
    }
    void set(double value) {
        type = ARG_TYPE_DOUBLE;
        doubleValue = value;
    }
    void set(bool value) {
        type = ARG_TYPE_BOOL;
        intValue = value?1:0;
    }
    void set(const char *value) {
        type = ARG_TYPE_STRING;
        ptrValue = (void *)value;
    }

    void set(JSValueRef value) {
        type = ARG_TYPE_JS_VALUE;
        ptrValue = (void*)value;
    }

    void setDartObject(void *ptr) {
        type = ARG_TYPE_DART_OBJECT;
        ptrValue = ptr;
    }

    void setDartClass(int id) {
        type = ARG_TYPE_DART_CLASS;
        intValue = id;
    }
    void setPointer(void *ptr) {
        type = ARG_TYPE_RAW_POINTER;
        ptrValue = ptr;
    }
};

//std::string _testString;

struct JsPromise {
    JSValue *target = nil;
    JSValue *success = nil;
    JSValue *failed = nil;

    void free(JSContext *ctx) {
        [success release];
        [failed release];
        [target release];
    }
};

struct JsMember {
    const char  *name;
    uint32_t    type;

    bool isStatic() const {
        return type & MEMBER_STATIC;
    }
};

struct JsClass {
    const char  *name;
    int         members_length;
    JsMember    *members;
};

using namespace std;

class JsContext {
    JsArgument *arguments;
    JsArgument *results;
    JsHandlers handlers;
    
    JsArgument tempArgument;
    
    JSContext *context;
    
    JSManagedValue *initObject;
    static JSStringRef privateKey;
    
    JSManagedValue *defineProperty;
    
    JSClassRef dataClassRef;
    vector<JSClassRef> classList;
    
    vector<JSValueRef> _arguments;
    string temp_string;
    set<JSObjectRef> createdObjects;
    
    static JSStringRef getPrivateKey() {
        if (privateKey == nullptr) {
            privateKey = JSStringCreateWithUTF8CString("_$c");
        }
        return privateKey;
    }
    
    static JsContext *getContext(JSContextRef ctx, JSValueRef* exception) {
        JSObjectRef keyData = (JSObjectRef)JSObjectGetProperty(ctx,
                                                               JSContextGetGlobalObject(ctx),
                                                               getPrivateKey(),
                                                               exception);
        if (*exception != nullptr) return nullptr;
        return (JsContext *)JSObjectGetPrivate(keyData);
    }
    
    char *copyString(const char *cstr) {
        size_t len = strlen(cstr);
        char *newstr = (char *)malloc(len + 1);
        memcpy(newstr, cstr, len);
        newstr[len] = 0;
        return newstr;
    }
    char *copyString(JSStringRef str) {
        size_t len = JSStringGetMaximumUTF8CStringSize(str);
        char *newstr = (char *)malloc(len);
        JSStringGetUTF8CString(str, newstr, len);
        return newstr;
    }
//    static const char *staticExceptionString(JSContextRef ctx, JSValueRef ex) {
//        JSStringRef str = JSValueToStringCopy(ctx,
//                            ex, nullptr);
//        size_t len = JSStringGetMaximumUTF8CStringSize(str);
//        _testString.resize(len);
//        size_t ret_len = JSStringGetUTF8CString(str, (char *)_testString.data(), len);
//        _testString.resize(ret_len - 1);
//        return _testString.c_str();
//    }
    const char *exceptionString(JSValueRef ex) {
        JSStringRef str = JSValueToStringCopy(context.JSGlobalContextRef,
                            ex, nullptr);
        size_t len = JSStringGetMaximumUTF8CStringSize(str);
        temp_string.resize(len);
        size_t ret_len = JSStringGetUTF8CString(str, (char *)temp_string.data(), len);
        temp_string.resize(ret_len - 1);
        return temp_string.c_str();
    }
    
    static int getPrivateID(JSContextRef ctx, JSObjectRef obj, JSValueRef* exception) {
        if (JSObjectHasProperty(ctx,
                                obj,
                                getPrivateKey())) {
            JSValueRef value = JSObjectGetProperty(ctx,
                                                   obj,
                                                   getPrivateKey(),
                                                   exception);
            if (*exception != nullptr) return -1;
            return (int)JSValueToNumber(ctx, value, exception);
        } else {
            return -1;
        }
    }
    
    static JSObjectRef constructor(JSContextRef ctx, JSObjectRef constructor, size_t argumentCount, const JSValueRef arguments[], JSValueRef* exception) {
        JSValueRef keyObject = JSObjectGetProperty(ctx, JSContextGetGlobalObject(ctx), getPrivateKey(), exception);
        if (*exception != nullptr) return nullptr;
        JsContext *self = (JsContext *)JSObjectGetPrivate((JSObjectRef)keyObject);
        if (*exception != nullptr) return nullptr;
        
        int cid = getPrivateID(ctx, constructor, exception);
        if (cid < 0) return nullptr;
        JSClassRef classRef = self->classList[cid];
        JSObjectRef objectRef = JSObjectMake(ctx, classRef, self);
        self->createdObjects.insert(objectRef);
        setPrivateKey(ctx, objectRef, JSValueMakeNumber(ctx, cid));
        
        if (argumentCount == 1 &&
            JSValueIsEqual(ctx, arguments[0],
                           self->initObject.value.JSValueRef, exception)) {
        } else {
            self->arguments[0].set(cid);
            self->arguments[1].setPointer(objectRef);
            for (int i = 0; i < argumentCount; ++i) {
                self->setArgument(self->arguments[2 + i], arguments[i]);
            }
            int ret = self->toDartAction(DART_ACTION_CONSTRUCTOR, (int)argumentCount + 2);
            if (ret >= 0) {
                
            } else {
                return nullptr;
            }
        }
        
        return objectRef;
    }
    
    static void finalizer(JSObjectRef object) {
        JsContext *self = (JsContext *)JSObjectGetPrivate(object);
        if (self) {
            self->arguments[0].setPointer(object);
            self->toDartAction(DART_ACTION_DELETE, 1);
            self->createdObjects.erase(object);
        }
    }
    
    static JSValueRef static_call(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef* exception) {
        JsContext *self = getContext(ctx, exception);
        if (*exception != nullptr) return nullptr;
        
        int methodId = self->getPrivateID(ctx, function, exception);
        if (methodId < 0) return nullptr;
        int classId = self->getPrivateID(ctx, thisObject, exception);
        if (classId < 0) return nullptr;
        
        if (argumentCount > self->handlers.maxArguments - 2) {
            self->context.exception = [JSValue valueWithNewErrorFromMessage:[NSString stringWithFormat:@"Too many arguments (%d)", (int)argumentCount]
                                                                  inContext:self->context];
            return nullptr;
        }
        self->arguments[0].set(classId);
        self->arguments[1].set(methodId);
        for (int i = 0; i < argumentCount; ++i) {
            self->setArgument(self->arguments[2 + i], arguments[i]);
        }
        int ret = self->toDartAction(DART_ACTION_CALL, 2 + (int)argumentCount);
        if (ret >= 0) {
            return self->getArgument(self->results[0]);
        }
        return nullptr;
    }
    
    static JSValueRef member_call(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef* exception) {
        JsContext *self = getContext(ctx, exception);
        if (*exception != nullptr) return nullptr;
        
        int methodId = self->getPrivateID(ctx, function, exception);
        if (methodId < 0) return nullptr;
        int classId = self->getPrivateID(ctx, thisObject, exception);
        if (classId < 0) return nullptr;
        
        if (argumentCount > self->handlers.maxArguments - 3) {
            self->context.exception = [JSValue valueWithNewErrorFromMessage:[NSString stringWithFormat:@"Too many arguments (%d)", (int)argumentCount]
                                                                  inContext:self->context];
            return nullptr;
        }
        self->arguments[0].set(classId);
        self->arguments[1].set(methodId);
        self->arguments[2].setPointer(thisObject);
        
        for (int i = 0; i < argumentCount; ++i) {
            self->setArgument(self->arguments[3 + i], arguments[i]);
        }
        int ret = self->toDartAction(DART_ACTION_CALL, 3 + (int)argumentCount);
        if (ret >= 0) {
            return self->getArgument(self->results[0]);
        }
        return nullptr;
    }
    
    
    static JSValueRef static_getter(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef* exception) {
        JsContext *self = getContext(ctx, exception);
        if (*exception != nullptr) return nullptr;
        
        int methodId = self->getPrivateID(ctx, function, exception);
        if (methodId < 0) return nullptr;
        int classId = self->getPrivateID(ctx, thisObject, exception);
        if (classId < 0) return nullptr;
        
        self->arguments[0].set(classId);
        self->arguments[1].set(methodId);
        int ret = self->toDartAction(DART_ACTION_CALL, 2);
        if (ret >= 0) {
            return self->getArgument(self->results[0]);
        }
        return nullptr;
    }
    
    static JSValueRef static_setter(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef* exception) {
        JsContext *self = getContext(ctx, exception);
        if (*exception != nullptr) return nullptr;
        
        int methodId = self->getPrivateID(ctx, function, exception);
        if (methodId < 0) return nullptr;
        int classId = self->getPrivateID(ctx, thisObject, exception);
        if (classId < 0) return nullptr;
        
        self->arguments[0].set(classId);
        self->arguments[1].set(methodId);
        self->setArgument(self->arguments[2], arguments[0]);
        int ret = self->toDartAction(DART_ACTION_CALL, 3);
        if (ret >= 0) {
            return JSValueMakeUndefined(ctx);
        }
        return nullptr;
    }
    
    static JSValueRef member_getter(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef* exception) {
        JsContext *self = getContext(ctx, exception);
        if (*exception != nullptr) return nullptr;
        
        int methodId = self->getPrivateID(ctx, function, exception);
        if (methodId < 0) return nullptr;
        int classId = self->getPrivateID(ctx, thisObject, exception);
        if (classId < 0) return nullptr;
        
        self->arguments[0].set(classId);
        self->arguments[1].set(methodId);
        self->arguments[2].setPointer(thisObject);
        
        int ret = self->toDartAction(DART_ACTION_CALL, 3);
        if (ret >= 0) {
            return self->getArgument(self->results[0]);
        }
        return nullptr;
    }
    
    static JSValueRef member_setter(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef* exception) {
        JsContext *self = getContext(ctx, exception);
        if (*exception != nullptr) return nullptr;
        
        int methodId = self->getPrivateID(ctx, function, exception);
        if (methodId < 0) return nullptr;
        int classId = self->getPrivateID(ctx, thisObject, exception);
        if (classId < 0) return nullptr;
        
        self->arguments[0].set(classId);
        self->arguments[1].set(methodId);
        self->arguments[2].setPointer(thisObject);
        self->setArgument(self->arguments[3], arguments[0]);
        
        int ret = self->toDartAction(DART_ACTION_CALL, 4);
        if (ret >= 0) {
            return self->getArgument(self->results[0]);
        }
        return nullptr;
    }
    
    static void setPrivateKey(JSContextRef ctx, JSObjectRef obj, JSValueRef key) {
        JSObjectSetProperty(ctx,
                            obj,
                            getPrivateKey(),
                            key,
                            kJSPropertyAttributeReadOnly|kJSPropertyAttributeDontDelete,
                            nullptr);
    }
    
    bool setArgument(JsArgument &argument, JSValueRef value) {
        JSContextRef ctx = context.JSGlobalContextRef;
        if (JSValueIsNumber(ctx, value)) {
            double num = JSValueToNumber(ctx, value, nullptr);
            int64_t inum = num;
            if (num == inum) {
                if (inum >= _Int32Min && inum <= _Int32Max) {
                    argument.set((int)inum);
                } else {
                    argument.set(inum);
                }
            } else {
                argument.set(num);
            }
        } else if (JSValueIsBoolean(ctx, value)) {
            argument.set(JSValueToBoolean(ctx, value));
        } else if (JSValueIsString(ctx, value)) {
            argument.type = ARG_TYPE_JS_STRING;
            argument.ptrValue = (void *)value;
        } else if (JSValueIsObject(ctx, value)) {
            argument.set(value);
        } else {
            argument.setNull();
        }
        return false;
    }

    JSValueRef getArgument(const JsArgument &argument) {
        JSContextRef ctx = context.JSGlobalContextRef;
        switch (argument.type) {
            case ARG_TYPE_NULL:
                return JSValueMakeNull(ctx);
            case ARG_TYPE_INT32:
                return JSValueMakeNumber(ctx, argument.intValue);
            case ARG_TYPE_INT64:
                return JSValueMakeNumber(ctx, argument.intValue);
            case ARG_TYPE_DOUBLE:
                return JSValueMakeNumber(ctx, argument.doubleValue);
            case ARG_TYPE_BOOL:
                return JSValueMakeBoolean(ctx, argument.intValue != 0);
            case ARG_TYPE_STRING: {
                JSStringRef string = JSStringCreateWithUTF8CString((const char *)argument.ptrValue);
                JSValueRef value = JSValueMakeString(ctx, string);
                JSStringRelease(string);
                return value;
            }
            case ARG_TYPE_JS_STRING:
                return (JSValueRef)argument.ptrValue;
            case ARG_TYPE_MANAGED_VALUE:
                return [(JSManagedValue *)argument.ptrValue value].JSValueRef;
            case ARG_TYPE_JS_VALUE:
                return (JSValueRef)argument.ptrValue;
            case ARG_TYPE_PROMISE: {
//                    JsPromise *promise = (JsPromise *)argument.ptrValue;
//                    return JS_DupValue(context, promise->target);
            }
        }
        return JSValueMakeUndefined(ctx);
    }
    
public:
    JsContext(JsArgument *arguments,
              JsArgument *results,
              JsHandlers *handlers) :
    arguments(arguments),
    results(results),
    handlers(*handlers) {
        context = [[JSContext alloc] init];
        initObject = [[JSManagedValue alloc] initWithValue:[JSValue valueWithNewObjectInContext:context]];
        
        JSClassDefinition def = kJSClassDefinitionEmpty;
        dataClassRef = JSClassCreate(&def);
        
        JSObjectRef wrap = JSObjectMake(context.JSGlobalContextRef, dataClassRef, this);
        JSObjectSetProperty(context.JSGlobalContextRef,
                            JSContextGetGlobalObject(context.JSGlobalContextRef),
                            getPrivateKey(),
                            wrap,
                            kJSPropertyAttributeReadOnly|kJSPropertyAttributeDontDelete,
                            NULL);
        
        defineProperty = [[JSManagedValue alloc] initWithValue:
                          [context evaluateScript:@"Object.defineProperty"]];
    }
    
    ~JsContext() {
        for (auto it = classList.begin(); it != classList.end(); ++it) {
            JSClassRelease(*it);
        }
        [initObject release];
        [defineProperty release];
        
        for (auto it = createdObjects.begin(); it != createdObjects.end(); ++it) {
            JSObjectSetPrivate(*it, nullptr);
        }
        
        JSClassRelease(dataClassRef);
        [context release];
    }
    
    int toDartAction(int type, int argc) {
        int ret = handlers.toDartAction(this, type, argc);
        if (ret < 0) {
            if (ret == -1) {
                context.exception = [JSValue valueWithJSValueRef:getArgument(results[0])
                                                       inContext:context];
            } else {
                context.exception = [JSValue valueWithNewErrorFromMessage:[NSString stringWithFormat:@"Unkown Error (%d)", ret]
                                                                inContext:context];
            }
        }
        return ret;
    }
    
    int action(int type, int argc) {
        switch (type) {
            case JS_ACTION_EVAL: {
                if (argc == 2 &&
                        arguments[0].type == ARG_TYPE_STRING &&
                        arguments[1].type == ARG_TYPE_STRING) {
                    const char *code = (const char *)arguments[0].ptrValue;
                    const char *filename = (const char *)arguments[1].ptrValue;
                    JSValue *value = [context evaluateScript:[NSString stringWithUTF8String:code]
                              withSourceURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:filename]]];
                    setArgument(results[0], value.JSValueRef);
                    return 1;
                }
                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_TO_STRING: {
                if (argc == 1 && arguments[0].type == ARG_TYPE_MANAGED_VALUE) {
                    JSManagedValue *value = (JSManagedValue *)arguments[0].ptrValue;
                    NSString *str = value.value.toString;
                    results[0].set(copyString(str.UTF8String));
                    return 1;
                }
                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_SET: {
                if (argc == 3 &&
                arguments[0].type == ARG_TYPE_MANAGED_VALUE &&
                arguments[1].type == ARG_TYPE_STRING) {
                    JSManagedValue *value = (JSManagedValue *)arguments[0].ptrValue;
                    const char *name = (const char *)arguments[1].ptrValue;
                    JSValueRef val = getArgument(arguments[2]);
                    JSContextRef ctx = context.JSGlobalContextRef;
                    
                    JSStringRef keyStr = JSStringCreateWithUTF8CString(name);
                    JSValueRef exception = nullptr;
                    JSObjectSetProperty(ctx,
                                        (JSObjectRef)value.value.JSValueRef,
                                        keyStr,
                                        val,
                                        kJSPropertyAttributeNone,
                                        &exception);
                    JSStringRelease(keyStr);
                    if (exception) {
                        results[0].set(exceptionString(exception));
                        return -1;
                    }
                    return 0;
                }
                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_GET: {
                if (argc == 2 &&
                        arguments[0].type == ARG_TYPE_MANAGED_VALUE &&
                        arguments[1].type == ARG_TYPE_STRING) {
                    JSManagedValue *value = (JSManagedValue *)arguments[0].ptrValue;
                    const char *name = (const char *)arguments[1].ptrValue;
                    JSContextRef ctx = context.JSGlobalContextRef;
                    
                    JSStringRef keyStr = JSStringCreateWithUTF8CString(name);
                    JSValueRef exception = nullptr;
                    JSValueRef val = JSObjectGetProperty(ctx,
                                                         (JSObjectRef)value.value.JSValueRef,
                                                         keyStr,
                                                         &exception);
                    JSStringRelease(keyStr);
                    
                    if (exception) {
                        results[0].set(exceptionString(exception));
                        return -1;
                    }
                    setArgument(results[0], val);
                    
                    return 1;
                }

                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_INVOKE: {
                if (argc >= 3 &&
                    arguments[0].type == ARG_TYPE_MANAGED_VALUE &&
                    arguments[1].type == ARG_TYPE_STRING &&
                    arguments[2].type == ARG_TYPE_INT32) {
                    JSManagedValue *value = (JSManagedValue *)arguments[0].ptrValue;
                    const char *name = (const char *)arguments[1].ptrValue;
                    
                    JSContextRef ctx = context.JSGlobalContextRef;
                    JSStringRef keyStr = JSStringCreateWithUTF8CString(name);
                    int argv = (int)arguments[2].intValue;
                    _arguments.resize(argv);
                    for (int i = 0; i < argv; ++i) {
                        _arguments[i] = getArgument(arguments[i + 3]);
                    }
                    
                    JSValueRef exception = nullptr;
                    JSValueRef func = JSObjectGetProperty(ctx,
                                        (JSObjectRef)value.value.JSValueRef,
                                        keyStr,
                                        &exception);
                    JSStringRelease(keyStr);
                    if (exception) {
                        results[0].set(exceptionString(exception));
                        return -1;
                    }
                    JSValueRef result = JSObjectCallAsFunction(ctx,
                                                               (JSObjectRef)func,
                                                               (JSObjectRef)value.value.JSValueRef,
                                                               argv,
                                                               _arguments.data(),
                                                               &exception);
                    
                    if (exception) {
                        results[0].set(exceptionString(exception));
                        return -1;
                    }
                    setArgument(results[0], result);
                    return 1;
                }

                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_BIND: {
                if (argc >= 1 && arguments[0].type == ARG_TYPE_MANAGED_VALUE) {
                    JSManagedValue *value = (JSManagedValue *)arguments[0].ptrValue;
                    JSContextRef ctx = context.JSGlobalContextRef;
                    JSObjectRef cons = (JSObjectRef)value.value.JSValueRef;
                    if (JSObjectIsConstructor(ctx, cons)) {
                        JSValueRef param = initObject.value.JSValueRef;
                        JSValueRef exception = nullptr;
                        JSObjectRef ret = JSObjectCallAsConstructor(ctx,
                                                                    cons,
                                                                    1,
                                                                    &param,
                                                                    &exception);
                        
                        if (exception) {
                            results[0].set(exceptionString(exception));
                            return -1;
                        }
                        if (JSObjectGetPrivate(ret) == this) {
                            results[0].setPointer(ret);
                            return 1;
                        }
                        results[0].set("Wrong result");
                        return -1;
                    } else {
                        results[0].set("Object is not constructor");
                        return -1;
                    }
                }

                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_PROMISE_COMPLETE: {
//                if (argc >= 2 &&
//                arguments[0].type == ARG_TYPE_PROMISE &&
//                arguments[1].type == ARG_TYPE_INT32) {
//                    JsPromise *promise = (JsPromise *)arguments[0].ptrValue;
//                    int type = arguments[1].intValue;
//                    if (type == 0) {
//                        JSValue value = getArgument(arguments[2]);
//                        JS_Call(context, promise->failed, promise->target, 1, &value);
//                        JS_FreeValue(context, value);
//                    } else if (type == 1) {
//                        JSValue value = getArgument(arguments[2]);
//                        JS_Call(context, promise->success, promise->target, 1, &value);
//                        JS_FreeValue(context, value);
//                    } else {
//                        JSValue value = JS_NULL;
//                        JS_Call(context, promise->success, promise->target, 1, &value);
//                    }
//                    promise->free(context);
//                    delete promise;
//                    return 0;
//                }
//                results[0].set("WrongArguments");
//                return -1;
            }
            case JS_ACTION_WRAP_FUNCTION: {
//                JsFunction *func = new JsFunction();
//                JSValue data = JS_NewBigInt64(context, (int64_t)func);
//                JSValue value = JS_NewCFunctionDataFinalizer(
//                        context, function_callback, 0, 0, 1,
//                        &data, function_finalizer, func);
//                func->value = value;
//                temp_results.push_back(value);
//                results[0].setPointer(JS_VALUE_GET_PTR(value));
//                return 1;
            }
            case JS_ACTION_CALL: {
                if (argc >= 2 &&
                arguments[0].type == ARG_TYPE_MANAGED_VALUE &&
                arguments[1].type == ARG_TYPE_INT32) {
                    JSContextRef ctx = context.JSGlobalContextRef;
                    JSManagedValue *value = (JSManagedValue *)arguments[0].ptrValue;
                    JSObjectRef func = (JSObjectRef)value.value.JSValueRef;
                    if (JSObjectIsFunction(ctx, func)) {
                        int argv = (int)arguments[1].intValue;

                        _arguments.resize(argv);
                        for (int i = 0; i < argv; ++i) {
                            _arguments[i] = getArgument(arguments[i + 2]);
                        }
                        JSValueRef exception = nullptr;
                        JSValueRef result = JSObjectCallAsFunction(ctx,
                                                                   func,
                                                                   JSContextGetGlobalObject(ctx),
                                                                   argv,
                                                                   _arguments.data(),
                                                                   &exception);

                        
                        if (exception) {
                            results[0].set(exceptionString(exception));
                            return -1;
                        }
                        setArgument(results[0], result);
                        return 1;
                    } else {
                        results[0].set("Object is not function");
                        return -1;
                    }
                }
                results[0].set("WrongArguments");
                return -1;
            }
        }
        results[0].set("NotImplement");
        return -1;
    }
    
    JsArgument *retainValue(void *ptr) {
        JSValueRef value = (JSValueRef)ptr;
        JSManagedValue *managedValue = [[JSManagedValue alloc] initWithValue:[JSValue valueWithJSValueRef:value inContext:context]];
        tempArgument.type = ARG_TYPE_MANAGED_VALUE;
        tempArgument.ptrValue = managedValue;
        return &tempArgument;
    }
    
    void* registerClass(JsClass *clazz, int cid) {
        auto ctx = context.JSGlobalContextRef;
        JSClassDefinition def = kJSClassDefinitionEmpty;
        def.className = clazz->name;
        def.finalize = finalizer;
        JSClassRef classRef = JSClassCreate(&def);
        JSObjectRef cons = JSObjectMakeConstructor(ctx,
                                                   classRef,
                                                   constructor);
        JSObjectSetProperty(ctx,
                            cons,
                            getPrivateKey(),
                            JSValueMakeNumber(ctx, cid),
                            kJSPropertyAttributeReadOnly|kJSPropertyAttributeDontDelete,
                            nullptr);
        
        JSObjectRef proto = (JSObjectRef)JSObjectGetPrototype(ctx, cons);
        
        struct Field {
            int setter = 0;
            int getter = 0;
            bool isStatic = false;
        };
        map<string, Field> fields;
        for (int i = 0; i < clazz->members_length; ++i) {
            const JsMember &member = clazz->members[i];
            if (member.type & MEMBER_CONSTRUCTOR) {
            } else if (member.type & MEMBER_FUNCTION) {
                JSStringRef jsName = JSStringCreateWithUTF8CString(member.name);
                if (member.isStatic()) {
                    JSObjectRef func = JSObjectMakeFunctionWithCallback(ctx,
                                                                        jsName,
                                                                        static_call);
                    setPrivateKey(ctx, func, JSValueMakeNumber(ctx, i));
                    JSObjectSetProperty(ctx,
                                        cons,
                                        jsName,
                                        func,
                                        kJSPropertyAttributeNone,
                                        nullptr);
                } else {
                    JSObjectRef func = JSObjectMakeFunctionWithCallback(ctx,
                                                                        jsName,
                                                                        member_call);
                    setPrivateKey(ctx, func, JSValueMakeNumber(ctx, i));
                    JSObjectSetProperty(ctx,
                                        proto,
                                        jsName,
                                        func,
                                        kJSPropertyAttributeNone,
                                        nullptr);
                }
                JSStringRelease(jsName);
            } else if (member.type & MEMBER_GETTER) {
                Field &field = fields[member.name];
                field.getter = i;
                field.isStatic = member.isStatic();
            } else if (member.type & MEMBER_SETTER) {
                Field &field = fields[member.name];
                field.setter = i;
                field.isStatic = member.isStatic();
            }
        }
        JSStringRef getStr = JSStringCreateWithUTF8CString("get");
        JSStringRef setStr = JSStringCreateWithUTF8CString("set");
        for (auto it = fields.begin(); it != fields.end(); ++it) {
            string name = it->first;
            const Field &field = it->second;
            JSStringRef jsName = JSStringCreateWithUTF8CString(name.c_str());
            JSObjectRef valueDef = JSObjectMake(ctx, NULL, NULL);
            JSObjectRef func = nullptr;
            if (field.isStatic) {
                if (field.getter != 0) {
                    func = JSObjectMakeFunctionWithCallback(ctx,
                                                            getStr,
                                                            static_getter);
                    setPrivateKey(ctx, func, JSValueMakeNumber(ctx, field.getter));
                    JSObjectSetProperty(ctx,
                                        valueDef,
                                        getStr,
                                        func,
                                        kJSPropertyAttributeNone,
                                        nullptr);
                }
                if (field.setter != 0) {
                    func = JSObjectMakeFunctionWithCallback(ctx,
                                                            getStr,
                                                            static_setter);
                    setPrivateKey(ctx, func, JSValueMakeNumber(ctx, field.setter));
                    JSObjectSetProperty(ctx,
                                        valueDef,
                                        setStr,
                                        func,
                                        kJSPropertyAttributeNone,
                                        nullptr);
                }
                
            } else {
                if (field.getter != 0) {
                    func = JSObjectMakeFunctionWithCallback(ctx,
                                                            getStr,
                                                            member_getter);
                    setPrivateKey(ctx, func, JSValueMakeNumber(ctx, field.getter));
                    JSObjectSetProperty(ctx,
                                        valueDef,
                                        getStr,
                                        func,
                                        kJSPropertyAttributeNone,
                                        nullptr);
                }
                if (field.setter != 0) {
                    func = JSObjectMakeFunctionWithCallback(ctx,
                                                            getStr,
                                                            member_setter);
                    setPrivateKey(ctx, func, JSValueMakeNumber(ctx, field.setter));
                    JSObjectSetProperty(ctx,
                                        valueDef,
                                        setStr,
                                        func,
                                        kJSPropertyAttributeNone,
                                        nullptr);
                }
            }
            JSValueRef arr[] = {
                field.isStatic ? cons : proto,
                JSValueMakeString(ctx, jsName),
                valueDef
            };
            JSObjectCallAsFunction(ctx,
                                   (JSObjectRef)defineProperty.value.JSValueRef,
                                   NULL,
                                   3,
                                   arr,
                                   nullptr);
            JSStringRelease(jsName);
        }
        JSStringRelease(getStr);
        JSStringRelease(setStr);
        
        JSStringRef className = JSStringCreateWithUTF8CString(clazz->name);
        JSObjectSetProperty(ctx,
                            JSContextGetGlobalObject(ctx),
                            className,
                            cons,
                            kJSPropertyAttributeNone,
                            nullptr);
        JSStringRelease(className);
        
        classList.push_back(classRef);
        return cons;
    }
    
    void clearCache() {
    }
    
    JsPromise *newPromise() {
        return nullptr;
    }
};

JSStringRef JsContext::privateKey = nullptr;

extern "C" {

JsContext *setupJsContext(
        JsArgument *arguments,
        JsArgument *results,
        JsHandlers *handlers) {
    return new JsContext(
            arguments,
            results,
            handlers);
}

void deleteJsContext(JsContext *self) {
    delete self;
}

int jsContextAction(JsContext *self, int type, int argc) {
    return self->action(type, argc);
}

const char *jsContextToStringPtr(JsContext *that, void *p) {
    NSString *str = (NSString *)p;
    const char *cstr = str.UTF8String;
    size_t len = strlen(cstr);
    char *newstr = (char *)malloc(len + 1);
    memcpy(newstr, cstr, len);
    newstr[len] = 0;
    return newstr;
}

void jsContextFreeStringPtr(JsContext *that, char * ptr) {
    free(ptr);
}

JsArgument *jsContextRetainValue(JsContext *self, void *ptr) {
    return self->retainValue(ptr);
}

void jsContextReleaseValue(JsContext *self, void *ptr) {
    JSManagedValue *value = (JSManagedValue *)ptr;
    [value release];
}

void jsContextClearCache(JsContext *self) {
    self->clearCache();
}

void *jsContextRegisterClass(JsContext *self, JsClass *clazz, int id) {
    return self->registerClass(clazz, id);
}

JsPromise *jsContextNewPromise(JsContext *self) {
    return self->newPromise();
}

int jsContextHasPendingJob(JsContext *self) {
    return 0;
}

int jsContextExecutePendingJob(JsContext *self) {
    return 0;
}

void jsContextSetup() {
}

}
