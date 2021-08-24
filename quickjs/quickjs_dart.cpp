//
//  quickjs_in.c
//  quickjs_osx
//
//  Created by gen on 12/4/20.
//  Copyright © 2020 nioqio. All rights reserved.
//

#include <stdio.h>
#include <stdarg.h>
#include <map>
#include <string>
#include <vector>
#include <list>
#include <stack>
#include <set>
#include <thread>
#include <pthread.h>
#include <sstream>
#include "quickjs_ext.h"
#include "quickjs-libc.h"
#include "cutils.h"
#include <memory.h>
#include <sys/time.h>
#include <cstring>


using namespace std;

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

const int MEMBER_FUNCTION     = 1 << 0;
const int MEMBER_CONSTRUCTOR  = 1 << 1;
const int MEMBER_GETTER       = 1 << 2;
const int MEMBER_SETTER       = 1 << 3;
const int MEMBER_STATIC       = 1 << 4;

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

    void setValue(JSValue value) {
        type = ARG_TYPE_JS_VALUE;
        ptrValue = JS_VALUE_GET_OBJ(value);
    }

    void setDartObject(void *ptr) {
        type = ARG_TYPE_DART_OBJECT;
        ptrValue = ptr;
    }

    void setDartClass(int id, void *ptr) {
        type = ARG_TYPE_DART_CLASS;
        intValue = id;
        ptrValue = ptr;
    }
    void setPointer(void *ptr) {
        type = ARG_TYPE_RAW_POINTER;
        ptrValue = ptr;
    }
};

struct JsMember {
    const char  *name;
    uint32_t    type;

    bool isStatic() const {
        return type & MEMBER_STATIC;
    }
};

struct JsFunction {
    JSValue value;
};

struct JsClass {
    const char  *name;
    int         members_length;
    JsMember    *members;
};

struct JsPromise {
    JSValue target = JS_UNDEFINED;
    JSValue success = JS_UNDEFINED;
    JSValue failed = JS_UNDEFINED;

    void free(JSContext *ctx) {
        JS_FreeValue(ctx, success);
        JS_FreeValue(ctx, failed);
        JS_FreeValue(ctx, target);
    }
};


bool isWordChar(char x) {
    return (x >= 'a' && x <= 'z') || (x >= 'A' && x <= 'Z') || (x >= '0' && x <= '9') || x == '_';
}

bool has_export(const string &strcode) {
    static string key("export");
    float found = false;
    size_t off = 0;
    while (off < strcode.size()) {
        size_t idx = strcode.find(key, off);
        if (idx < strcode.size()) {
            bool c1 = idx == 0 || !isWordChar(strcode[idx - 1]), c2 = (idx + key.size()) == strcode.size() || !isWordChar(strcode[idx + key.size()]);
            found = c1 && c2;
            if (found) break;
        }
        off = idx < strcode.size() ? idx + key.size() : idx;
    }
    return found;
}

class JsContext {
    JsArgument  *arguments;
    JsArgument  *results;

    JsHandlers handlers;

    JSAtom private_key;
    JSAtom class_private_key;
    JSAtom exports_key;
    JSAtom prototype_key;
    JSAtom toString_key;
    JSValue init_object;
//    JSValue create_operators;
//    JSAtom operator_set_atom;

    vector<JSValue> temp_results;

    static JSValue constructor(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv, int magic) {
        JsContext *self = (JsContext *)JS_GetContextOpaque(ctx);
        JSClassID classId = magic;

        if (argc > self->handlers.maxArguments - 2) {
            JS_ThrowInternalError(self->context, "Too many arguments (%d)", argc);
            return JS_EXCEPTION;
        }

        JSValue proto = JS_GetProperty(self->context, this_val, self->prototype_key);
        if (JS_IsException(proto)) {
            return JS_EXCEPTION;
        }
        JSValue obj = JS_NewObjectProtoClass(self->context, proto, classId);
        JS_FreeValue(self->context, proto);
        if (JS_IsException(obj)) {
            return JS_EXCEPTION;
        }
        void *ptr = JS_VALUE_GET_PTR(obj);

        if (argc == 1 && JS_VALUE_GET_PTR(argv[0]) == JS_VALUE_GET_PTR(self->init_object)) {
            JS_SetOpaque(obj, ptr);
            JS_SetProperty(ctx, obj, self->private_key, JS_NewBigInt64(self->context, (int64_t)ptr));
            return obj;
        } else {
            JSValue key = JS_GetProperty(ctx, this_val, self->class_private_key);
            int id = JS_VALUE_GET_INT(key);
            JS_FreeValue(ctx, key);

            self->arguments[0].set(id);
            self->arguments[1].setPointer(ptr);
            for (int i = 0; i < argc; ++i) {
                self->setArgument(self->arguments[2 + i], argv[i]);
            }

            int ret = self->toDartAction(DART_ACTION_CONSTRUCTOR, argc + 2);
            if (ret >= 0) {
                JS_SetOpaque(obj, ptr);
                JS_SetProperty(ctx, obj, self->private_key, JS_NewBigInt64(self->context, (int64_t)ptr));
                return obj;
            } else {
                JS_FreeValue(ctx, obj);
            }
            return JS_EXCEPTION;
        }
    }

    static JSValue static_getter(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv, int magic, JSValue *func_data) {
        JsContext *self = (JsContext *)JS_GetContextOpaque(ctx);
        int classId = JS_VALUE_GET_INT(func_data[0]);
        self->arguments[0].set(classId);
        self->arguments[1].set(magic);
        int ret = self->toDartAction(DART_ACTION_CALL, 2);
        if (ret >= 0) {
            return self->getArgument(self->results[0]);
        }
        return JS_EXCEPTION;
    }
    static JSValue static_setter(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv, int magic, JSValue *func_data) {
        JsContext *self = (JsContext *)JS_GetContextOpaque(ctx);
        int classId = JS_VALUE_GET_INT(func_data[0]);
        self->arguments[0].set(classId);
        self->arguments[1].set(magic);
        self->setArgument(self->arguments[2], argv[0]);
        int ret = self->toDartAction(DART_ACTION_CALL, 3);
        if (ret >= 0) {
            return self->getArgument(self->results[0]);
        }
        return JS_EXCEPTION;
    }
    static JSValue field_getter(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv, int magic, JSValue *func_data) {
        JsContext *self = (JsContext *)JS_GetContextOpaque(ctx);
        int classId = JS_VALUE_GET_INT(func_data[0]);
        self->arguments[0].set(classId);
        self->arguments[1].set(magic);
        self->arguments[2].setPointer(JS_VALUE_GET_PTR(this_val));
        int ret = self->toDartAction(DART_ACTION_CALL, 3);
        if (ret >= 0) {
            return self->getArgument(self->results[0]);
        }
        return JS_EXCEPTION;
    }
    static JSValue field_setter(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv, int magic, JSValue *func_data) {
        JsContext *self = (JsContext *)JS_GetContextOpaque(ctx);
        int classId = JS_VALUE_GET_INT(func_data[0]);

        self->arguments[0].set(classId);
        self->arguments[1].set(magic);
        self->arguments[2].setPointer(JS_VALUE_GET_PTR(this_val));
        self->setArgument(self->arguments[3], argv[0]);
        int ret = self->toDartAction(DART_ACTION_CALL, 4);
        if (ret >= 0) {
            return self->getArgument(self->results[0]);
        }
        return JS_EXCEPTION;
    }
    static JSValue static_call(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv, int magic, JSValue *func_data) {
        JsContext *self = (JsContext *)JS_GetContextOpaque(ctx);
        if (argc > self->handlers.maxArguments - 2) {
            JS_ThrowInternalError(self->context, "Too many arguments (%d)", argc);
            return JS_EXCEPTION;
        }
        int classId = JS_VALUE_GET_INT(func_data[0]);
        self->arguments[0].set(classId);
        self->arguments[1].set(magic);
        for (int i = 0; i < argc; ++i) {
            self->setArgument(self->arguments[2 + i], argv[i]);
        }

        int ret = self->toDartAction(DART_ACTION_CALL, 2 + argc);
        if (ret >= 0) {
            return self->getArgument(self->results[0]);
        }
        return JS_EXCEPTION;
    }
    static JSValue member_call(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv, int magic, JSValue *func_data) {
        JsContext *self = (JsContext *)JS_GetContextOpaque(ctx);
        if (argc > self->handlers.maxArguments - 3) {
            JS_ThrowInternalError(self->context, "Too many arguments (%d)", argc);
            return JS_EXCEPTION;
        }
        int classId = JS_VALUE_GET_INT(func_data[0]);

        self->arguments[0].set(classId);
        self->arguments[1].set(magic);
        self->arguments[2].setPointer(JS_VALUE_GET_PTR(this_val));

        for (int i = 0; i < argc; ++i) {
            self->setArgument(self->arguments[3 + i], argv[i]);
        }

        int ret = self->toDartAction(DART_ACTION_CALL, 3 + argc);
        if (ret >= 0) {
            return self->getArgument(self->results[0]);
        }
        return JS_EXCEPTION;
    }
    static void class_finalizer(JSRuntime *rt, JSValue val) {
        JsContext *self = (JsContext *)JS_GetRuntimeOpaque(rt);
        self->arguments[0].setPointer(JS_VALUE_GET_PTR(val));
        self->toDartAction(DART_ACTION_DELETE, 1);
    }

    char *copyString(const char *str) {
        size_t len = strlen(str);
        char *newstr = (char *)js_malloc(context, len + 1);
        memcpy(newstr, str, len);
        newstr[len] = 0;
        return newstr;
    }

    static void pathCombine(string &path, const string &seg) {
        if (seg == ".") {
        } else if (seg == "..") {
            while (path[path.length() - 1] == '/') {
                path.pop_back();
            }
            path.resize(path.find_last_of('/'));
        } else {
            if (path[path.length() - 1] == '/') {
                path += seg;
            } else {
                path.push_back('/');
                path += seg;
            }
        }
    }

    static char *module_name(JSContext *ctx,
            const char *module_base_name,
            const char *module_name, void *opaque) {
        JsContext *self = (JsContext *)opaque;
        self->arguments[0].set(module_base_name);
        self->arguments[1].set(module_name);
        int ret = self->toDartAction(DART_ACTION_MODULE_NAME, 2);
        if (ret > 0 && self->results[0].type == ARG_TYPE_STRING) {
            return self->copyString((const char *)self->results[0].ptrValue);
        } else {
            return nullptr;
        }
    }

    static JSModuleDef *module_loader(JSContext *ctx,
            const char *module_name, void *opaque) {
        JsContext *self = (JsContext *)opaque;
        self->arguments[0].set(module_name);
        int ret = self->toDartAction(DART_ACTION_LOAD_MODULE, 1);
        JSModuleDef *module = nullptr;
        if (ret > 0 && self->results[0].type == ARG_TYPE_STRING) {
            string strcode((const char *)self->results[0].ptrValue);
            if (!has_export(strcode)) {
                stringstream ss;
                ss << "const module = {exports: {}}; let exports = module.exports;" << endl;
                ss << strcode << endl;
                ss << "export default module.exports;" << endl;
                strcode = ss.str();
            }
            JSValue val = JS_Eval(self->context, strcode.data(),
                    (int)strcode.size(), module_name,
                    JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
            if (!JS_IsException(val)) {
                module = (JSModuleDef *)JS_VALUE_GET_PTR(val);
                JS_FreeValue(self->context, val);
            }
        }
        return module;
    }

    static JSValue consolePrint(JSContext *ctx, int type, int argc, JSValueConst *argv) {
        string str;
        for (int i = 0; i < argc; ++i) {
            const char *cstr = JS_ToCString(ctx, argv[i]);
            if (cstr) {
                str += cstr;
                JS_FreeCString(ctx, cstr);
                if (i != argc - 1) {
                    str += ',';
                }
            }
        }
        JSRuntime *runtime = JS_GetRuntime(ctx);
        JsContext *that = (JsContext *)JS_GetRuntimeOpaque(runtime);
        print(that, type, "%s", str.c_str());
        return JS_UNDEFINED;
    }

    string errorString(JSValue value) {
        stringstream ss;
        const char *str = JS_ToCString(context, value);
        if (str) {
            ss << str << endl;
            JS_FreeCString(context, str);
        }

        JSValue stack = JS_GetPropertyStr(context, value, "stack");
        if (!JS_IsException(stack)) {
            str = JS_ToCString(context, stack);
            if (str) {
                ss << str << endl;
                JS_FreeCString(context, str);
            }
            JS_FreeValue(context, stack);
        }

        return ss.str();
    }

    bool setArgument(JsArgument &argument, JSValue value) {
        auto tag = JS_VALUE_GET_TAG(value);
        switch (tag) {
            case JS_TAG_INT: {
                int32_t v = 0;
                JS_ToInt32(context, &v, value);
                argument.set(v);
                return false;
            }
            case JS_TAG_BIG_INT: {
                int64_t v = 0;
                JS_ToBigInt64(context, &v, value);
                argument.set(v);
                return false;
            }
            case JS_TAG_BIG_FLOAT: {
                double v = 0;
                JS_ToFloat64(context, &v, value);
                argument.set(v);
                return false;
            }
            case JS_TAG_FLOAT64: {
                double v = 0;
                JS_ToFloat64(context, &v, value);
                argument.set(v);
                return false;
            }
            case JS_TAG_BOOL: {
                argument.set((bool)JS_ToBool(context, value));
                return false;
            }
            case JS_TAG_STRING: {
                argument.type = ARG_TYPE_JS_STRING;
                argument.ptrValue = JS_VALUE_GET_PTR(value);
                return true;
            }
            case JS_TAG_OBJECT: {
                argument.setValue(value);
                return true;
            }

            default:
            {
                if (JS_TAG_IS_FLOAT64(tag)) {
                    double v = 0;
                    JS_ToFloat64(context, &v, value);
                    argument.set(v);
                    return true;
                }
            }
                break;
        }
        argument.setNull();
        return false;
    }

    JSValue getArgument(const JsArgument &argument) {
        switch (argument.type) {
            case ARG_TYPE_NULL:
                return JS_NULL;
            case ARG_TYPE_INT32:
                return JS_NewInt32(context, argument.intValue);
            case ARG_TYPE_INT64:
                return JS_NewInt64(context, argument.intValue);
            case ARG_TYPE_DOUBLE:
                return JS_NewFloat64(context, argument.doubleValue);
            case ARG_TYPE_BOOL:
                return JS_NewBool(context, argument.intValue != 0);
            case ARG_TYPE_STRING:
                return JS_NewString(context, (const char *)argument.ptrValue);
            case ARG_TYPE_JS_STRING:
                return JS_DupValue(context, JS_MKPTR(JS_TAG_STRING, argument.ptrValue));
            case ARG_TYPE_JS_VALUE:
            case ARG_TYPE_MANAGED_VALUE:
                return JS_DupValue(context, JS_MKPTR(JS_TAG_OBJECT, argument.ptrValue));
            case ARG_TYPE_PROMISE: {
                JsPromise *promise = (JsPromise *)argument.ptrValue;
                return JS_DupValue(context, promise->target);
            }
        }
        return JS_UNDEFINED;
    }

    static JSValue promise_init(JSContext *context, JSValueConst this_val, int argc, JSValueConst *argv, int magic, JSValue *func_data) {
        JsContext *self = (JsContext *)JS_GetContextOpaque(context);
        int64_t ptr;
        JS_ToBigInt64(context, &ptr, *func_data);
        JsPromise *pro = (JsPromise *)ptr;
        if (argc >= 2) {
            pro->success = JS_DupValue(context, argv[0]);
            pro->failed = JS_DupValue(context, argv[1]);
        } else {
            print(self, 2, "- WTF ? %d", argc);
        }
        return JS_UNDEFINED;
    }

    static JSValue function_callback(JSContext *context, JSValue this_val, int argc, JSValue *argv, int magic, JSValue *func_data) {
        JsContext *self = (JsContext *)JS_GetContextOpaque(context);
        if (argc > self->handlers.maxArguments - 1) {
            JS_ThrowInternalError(self->context, "Too many arguments (%d)", argc);
            return JS_EXCEPTION;
        }
        int64_t ptr;
        JS_ToBigInt64(context, &ptr, *func_data);

        JsFunction *func = (JsFunction*)ptr;
        self->arguments[0].setPointer(JS_VALUE_GET_PTR(func->value));

        for (int i = 0; i < argc; ++i) {
            self->setArgument(self->arguments[1 + i], argv[i]);
        }
        int ret = self->toDartAction(DART_ACTION_CALL_FUNCTION, argc + 1);
        if (ret == 0) {
            return JS_UNDEFINED;
        } else if (ret > 0) {
            return self->getArgument(self->results[0]);
        } else {
            return JS_EXCEPTION;
        }
    }

    static void function_finalizer(JSRuntime *rt, void *opaque) {
        JsContext *self = (JsContext *)JS_GetRuntimeOpaque(rt);
        JsFunction *func = (JsFunction *)opaque;
        self->arguments[0].setPointer(JS_VALUE_GET_PTR(func->value));
        self->toDartAction(DART_ACTION_DELETE, 1);
        delete func;
    }

    string temp_string;
    JsArgument tempArgument;
    vector<JSValue> classVector;
    JSValue promise;
    JSValue promiseResolve;

public:
    static JsContext *_temp;
    JSContext   *context;
    JSRuntime   *runtime;

    JsContext(
            JsArgument *arguments,
            JsArgument *results,
            JsHandlers *handlers) :
            arguments(arguments),
            results(results),
            handlers(*handlers) {
        _temp = this;
        runtime = JS_NewRuntime();
        JS_SetRuntimeOpaque(runtime, this);
        JS_SetModuleLoaderFunc(runtime, module_name, module_loader, this);

        context = JS_NewContext(runtime);
        JS_AddIntrinsicOperators(context);
        JS_AddIntrinsicRequire(context);
        JS_SetContextOpaque(context, this);

        private_key = JS_NewAtom(context, "_$tar");
        class_private_key = JS_NewAtom(context, "_$class");
        exports_key = JS_NewAtom(context, "exports");
        prototype_key = JS_NewAtom(context, "prototype");
        toString_key = JS_NewAtom(context, "toString");
        init_object = JS_NewObject(context);

        JSValue global = JS_GetGlobalObject(context);
        JSValue console = JS_NewObject(context);

        JS_SetPropertyStr(context, console, "log", JS_NewCFunction(context, [](JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv){
            consolePrint(ctx, 0, argc, argv);
            return JS_UNDEFINED;
        }, "log", 1));
        JS_SetPropertyStr(context, console, "warn", JS_NewCFunction(context, [](JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv){
            consolePrint(ctx, 1, argc, argv);
            return JS_UNDEFINED;
        }, "warn", 1));
        JS_SetPropertyStr(context, console, "error", JS_NewCFunction(context, [](JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv){
            consolePrint(ctx, 2, argc, argv);
            return JS_UNDEFINED;
        }, "error", 1));
        JS_SetPropertyStr(context, global, "console", console);


        JSAtom globalAtom = JS_NewAtom(context, "global");
        JS_DefinePropertyGetSet(context, global, globalAtom, JS_NewCFunction(context, [](JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv){
            return JS_GetGlobalObject(ctx);
        }, "global", 0), JS_UNDEFINED, 0);
        JS_FreeAtom(context, globalAtom);

        promise = JS_GetPropertyStr(context, global, "Promise");
        promiseResolve = JS_GetPropertyStr(context, promise, "resolve");

        JS_FreeValue(context, global);
    }

    ~JsContext() {
        for (auto it = classVector.begin(); it != classVector.end(); ++it) {
            JS_FreeValue(context, *it);
        }
        classVector.clear();
        JS_FreeAtom(context, private_key);
        JS_FreeAtom(context, class_private_key);
        JS_FreeAtom(context, exports_key);
        JS_FreeAtom(context, prototype_key);
        JS_FreeAtom(context, toString_key);
        JS_FreeValue(context, init_object);
        JS_FreeValue(context, promise);
        JS_FreeValue(context, promiseResolve);

        JS_FreeContext(context);
        JS_FreeRuntime(runtime);
        if (_temp == this)
            _temp = nullptr;
    }

    static void printError(JsContext *that, JSValue value, const char *prefix) {
        stringstream ss;
        JSContext *context = that->context;
        const char *str = JS_ToCString(context, value);
        if (str) {
            ss << str << endl;
            JS_FreeCString(context, str);
        }

        JSValue stack = JS_GetPropertyStr(context, value, "stack");
        if (!JS_IsException(stack)) {
            str = JS_ToCString(context, stack);
            if (str) {
                ss << str << endl;
                JS_FreeCString(context, str);
            }
            JS_FreeValue(context, stack);
        }

        string output = ss.str();
        if (prefix) {
            print(that, 2, "%s: %s", prefix, output.c_str());
        } else {
            print(that, 2, "%s", output.c_str());
        }
    }

    int toDartAction(int type, int argc) {
        int ret = handlers.toDartAction(this, type, argc);
        if (ret < 0) {
            if (ret == -1) {
                JSValue value = getArgument(results[0]);
                JS_Throw(context, value);
            } else {
                JS_ThrowInternalError(context, "Unkown Error (%d)", ret);
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
                    JSValue val = JS_Eval(context, code, strlen(code), filename, JS_EVAL_TYPE_GLOBAL);
                    if (JS_IsException(val)) {
                        JSValue ex = JS_GetException(context);
                        temp_string = errorString(ex);
                        JS_FreeValue(context, ex);
                        results[0].set(temp_string.c_str());
                        return -1;
                    } else {
                        if (setArgument(results[0], val)) {
                            temp_results.push_back(val);
                        } else {
                            JS_FreeValue(context, val);
                        }
                        return 1;
                    }
                }
                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_TO_STRING: {
                if (argc == 1 && arguments[0].type == ARG_TYPE_MANAGED_VALUE) {
                    JSValue value = JS_MKPTR(JS_TAG_OBJECT, arguments[0].ptrValue);
                    results[0].set(JS_ToCString(context, value));
                    return 1;
                }
                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_SET: {
                if (argc == 3 &&
                arguments[0].type == ARG_TYPE_MANAGED_VALUE &&
                        (arguments[1].type == ARG_TYPE_STRING ||
                        arguments[1].type == ARG_TYPE_INT32)) {
                    JSValue value = JS_MKPTR(JS_TAG_OBJECT, arguments[0].ptrValue);
                    JSValue val = getArgument(arguments[2]);

                    JSAtom atom;
                    if (arguments[1].type == ARG_TYPE_STRING) {
                        const char *name = (const char *)arguments[1].ptrValue;
                        atom = JS_NewAtom(context, name);
                    } else {
                        atom = JS_NewAtomUInt32(context, arguments[1].intValue);
                    }

                    bool res = JS_SetProperty(context, value, atom, val) == TRUE;
                    JS_FreeAtom(context, atom);

                    if (res) {
                        JS_FreeValue(context, val);
                        return 0;
                    } else {
                        JSValue ex = JS_GetException(context);
                        temp_string = errorString(ex);
                        JS_FreeValue(context, ex);
                        results[0].set(temp_string.c_str());
                        return -1;
                    }
                }
                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_GET: {
                if (argc == 2 &&
                        arguments[0].type == ARG_TYPE_MANAGED_VALUE &&
                        (arguments[1].type == ARG_TYPE_STRING ||
                         arguments[1].type == ARG_TYPE_INT32)) {
                    JSValue value = JS_MKPTR(JS_TAG_OBJECT, arguments[0].ptrValue);

                    JSAtom atom;
                    if (arguments[1].type == ARG_TYPE_STRING) {
                        const char *name = (const char *)arguments[1].ptrValue;
                        atom = JS_NewAtom(context, name);
                    } else {
                        atom = JS_NewAtomUInt32(context, arguments[1].intValue);
                    }

                    JSValue val = JS_GetProperty(context, value, atom);
                    JS_FreeAtom(context, atom);

                    if (JS_IsException(val)) {
                        JSValue ex = JS_GetException(context);
                        temp_string = errorString(ex);
                        JS_FreeValue(context, ex);
                        results[0].set(temp_string.c_str());
                        return -1;
                    } else {
                        if (setArgument(results[0], val)) {
                            temp_results.push_back(val);
                        } else {
                            JS_FreeValue(context, val);
                        }
                        return 1;
                    }
                }

                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_INVOKE: {
                if (argc >= 3 &&
                    arguments[0].type == ARG_TYPE_MANAGED_VALUE &&
                    arguments[1].type == ARG_TYPE_STRING &&
                    arguments[2].type == ARG_TYPE_INT32) {
                    JSValue value = JS_MKPTR(JS_TAG_OBJECT, arguments[0].ptrValue);
                    const char *name = (const char *)arguments[1].ptrValue;
                    JSAtom atom = JS_NewAtom(context, name);
                    int argv = arguments[2].intValue;
                    vector<JSValue> _arguments;
                    _arguments.resize(argv);
                    for (int i = 0; i < argv; ++i) {
                        _arguments[i] = getArgument(arguments[i + 3]);
                    }

                    JSValue val = JS_Invoke(context, value, atom, argv, _arguments.data());
                    for (int i = 0; i < argv; ++i) {
                        JS_FreeValue(context, _arguments[i]);
                    }
                    JS_FreeAtom(context, atom);

                    if (JS_IsException(val)) {
                        JSValue ex = JS_GetException(context);
                        temp_string = errorString(ex);
                        JS_FreeValue(context, ex);
                        results[0].set(temp_string.c_str());
                        return -1;
                    } else {
                        if (setArgument(results[0], val)) {
                            temp_results.push_back(val);
                        } else {
                            JS_FreeValue(context, val);
                        }
                        return 1;
                    }
                }

                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_BIND: {
                if (argc >= 1 && arguments[0].type == ARG_TYPE_MANAGED_VALUE) {
                    JSValue value = JS_MKPTR(JS_TAG_OBJECT, arguments[0].ptrValue);
                    if (JS_IsConstructor(context, value)) {
                        JSValue ret = JS_CallConstructor(context, value, 1, &init_object);
                        if (JS_IsException(ret)) {
                            JSValue ex = JS_GetException(context);
                            temp_string = errorString(ex);
                            JS_FreeValue(context, ex);
                            results[0].set(temp_string.c_str());
                            return -1;
                        } else {
                            if (JS_HasProperty(context, ret, private_key)) {
                                temp_results.push_back(ret);
                                results[0].setPointer(JS_VALUE_GET_PTR(ret));
                                return 1;
                            } else {
                                JS_FreeValue(context, ret);
                                results[0].set("Wrong result");
                                return -1;
                            }
                        }
                    } else {
                        results[0].set("Object is not constructor");
                        return -1;
                    }
                }

                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_PROMISE_COMPLETE: {
                if (argc >= 2 &&
                arguments[0].type == ARG_TYPE_PROMISE &&
                arguments[1].type == ARG_TYPE_INT32) {
                    JsPromise *promise = (JsPromise *)arguments[0].ptrValue;
                    int type = arguments[1].intValue;
                    if (type == 0) {
                        JSValue value = getArgument(arguments[2]);
                        JS_Call(context, promise->failed, promise->target, 1, &value);
                        JS_FreeValue(context, value);
                    } else if (type == 1) {
                        JSValue value = getArgument(arguments[2]);
                        JS_Call(context, promise->success, promise->target, 1, &value);
                        JS_FreeValue(context, value);
                    } else {
                        JSValue value = JS_NULL;
                        JS_Call(context, promise->success, promise->target, 1, &value);
                    }
                    promise->free(context);
                    delete promise;
                    return 0;
                }
                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_WRAP_FUNCTION: {
                JsFunction *func = new JsFunction();
                JSValue data = JS_NewBigInt64(context, (int64_t)func);
                JSValue value = JS_NewCFunctionDataFinalizer(
                        context, function_callback, 0, 0, 1,
                        &data, function_finalizer, func);
                func->value = value;
                void *ptr = JS_VALUE_GET_PTR(value);
                JS_SetProperty(context, value, private_key,
                        JS_NewBigInt64(context, (int64_t)ptr));
                temp_results.push_back(value);
                results[0].setPointer(JS_VALUE_GET_PTR(value));
                return 1;
            }
            case JS_ACTION_CALL: {
                if (argc >= 2 &&
                arguments[0].type == ARG_TYPE_MANAGED_VALUE &&
                arguments[1].type == ARG_TYPE_INT32) {
                    JSValue value = JS_MKPTR(JS_TAG_OBJECT, arguments[0].ptrValue);
                    if (JS_IsFunction(context, value)) {
                        JSValue global = JS_GetGlobalObject(context);
                        int argv = arguments[1].intValue;

                        vector<JSValue> _arguments;
                        _arguments.resize(argv);
                        for (int i = 0; i < argv; ++i) {
                            _arguments[i] = getArgument(arguments[i + 2]);
                        }
                        JSValue val = JS_Call(context,
                                value,
                                global,
                                argv,
                                _arguments.data());
                        JS_FreeValue(context, global);
                        for (int i = 0; i < argv; ++i) {
                            JS_FreeValue(context, _arguments[i]);
                        }

                        if (JS_IsException(val)) {
                            JSValue ex = JS_GetException(context);
                            temp_string = errorString(ex);
                            JS_FreeValue(context, ex);
                            results[0].set(temp_string.c_str());
                            return -1;
                        } else {
                            if (setArgument(results[0], val)) {
                                temp_results.push_back(val);
                            } else {
                                JS_FreeValue(context, val);
                            }
                            return 1;
                        }
                    } else {
                        results[0].set("Object is not function");
                        return -1;
                    }
                }
                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_RUN: {
                if (argc == 2 &&
                    arguments[0].type == ARG_TYPE_STRING &&
                    arguments[1].type == ARG_TYPE_STRING) {
                    const char *code = (const char *)arguments[0].ptrValue;
                    const char *filename = (const char *)arguments[1].ptrValue;

                    string strcode(code);
                    if (!has_export(strcode)) {
                        stringstream ss;
                        ss << "const module = {exports: {}}; let exports = module.exports;" << endl;
                        ss << code << endl;
                        ss << "export default module.exports;" << endl;
                        strcode = ss.str();
                    }

                    JSValue ret = JS_Eval(context, strcode.c_str(), strcode.size(), filename,
                            JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
                    if (JS_IsException(ret)) {
                        JSValue ex = JS_GetException(context);
                        temp_string = errorString(ex);
                        JS_FreeValue(context, ex);
                        results[0].set(temp_string.c_str());
                        return -1;
                    } else {
                        int tag = JS_VALUE_GET_TAG(ret);
                        if (tag == JS_TAG_MODULE) {
                            JSValue val = JS_EvalFunction(context, ret);
                            if (JS_IsException(val)) {
                                JSValue ex = JS_GetException(context);
                                temp_string = errorString(ex);
                                JS_FreeValue(context, ex);
                                results[0].set(temp_string.c_str());
                                return -1;
                            } else {
                                JSModuleDef *module = (JSModuleDef *)JS_VALUE_GET_PTR(ret);
                                JSValue data = JS_GetModuleDefault(context, module);
                                if (setArgument(results[0], data)) {
                                    temp_results.push_back(data);
                                } else {
                                    JS_FreeValue(context, data);
                                }
                                return 1;
                            }
                        } else {
                            results[0].set("Script is not a module");
                            return -1;
                        }

                    }
                }
                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_RUN_PROMISE: {
                if (argc == 3 &&
                    arguments[0].type == ARG_TYPE_MANAGED_VALUE &&
                    arguments[1].type == ARG_TYPE_MANAGED_VALUE &&
                    arguments[2].type == ARG_TYPE_MANAGED_VALUE) {
                    JSValue obj = JS_MKPTR(JS_TAG_OBJECT, arguments[0].ptrValue);
                    JSValue resolve = JS_MKPTR(JS_TAG_OBJECT, arguments[1].ptrValue);
                    JSValue reject = JS_MKPTR(JS_TAG_OBJECT, arguments[2].ptrValue);

                    JSValue resolved = JS_Call(context, promiseResolve, promise, 1, &obj);
                    JSAtom then = JS_NewAtom(context, "then");
                    JSAtom _catch = JS_NewAtom(context, "catch");
                    JS_FreeValue(context, JS_Invoke(context, resolved, then, 1, &resolve));
                    JS_FreeValue(context, JS_Invoke(context, resolved, _catch, 1, &reject));
                    JS_FreeAtom(context, then);
                    JS_FreeAtom(context, _catch);
                    JS_FreeValue(context, resolved);

                    return 0;
                }
                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_PROPERTY_NAMES: {
                if (argc == 1 && arguments[0].type == ARG_TYPE_MANAGED_VALUE) {
                    JSValue obj = JS_MKPTR(JS_TAG_OBJECT, arguments[0].ptrValue);
                    JSPropertyEnum *propertyEnum = nullptr;
                    uint32_t length = 0;
                    int ret = JS_GetOwnPropertyNames(
                            context, &propertyEnum, &length, obj,
                            JS_GPN_STRING_MASK | JS_GPN_SYMBOL_MASK);
                    if (ret < 0) {
                        JSValue ex = JS_GetException(context);
                        temp_string = errorString(ex);
                        JS_FreeValue(context, ex);
                        results[0].set(temp_string.c_str());
                        return -1;
                    } else {
                        temp_results.clear();
                        for (int i = 0; i < length; ++i) {
                            const char * chs = JS_AtomToCString(context, propertyEnum[i].atom);
                            if (i != 0) {
                                temp_string.push_back(',');
                            }
                            temp_string += chs;
                        }
                        results[0].set(temp_string.c_str());
                        return 1;
                    }
                }
                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_NEW_OBJECT: {
                JSValue obj = JS_NewObject(context);
                results[0].setPointer(JS_VALUE_GET_PTR(obj));
                temp_results.push_back(obj);
                return 1;
            }
            case JS_ACTION_IS_ARRAY: {
                if (argc == 1 && arguments[0].type == ARG_TYPE_MANAGED_VALUE) {
                    JSValue obj = JS_MKPTR(JS_TAG_OBJECT, arguments[0].ptrValue);
                    results[0].set((bool)JS_IsArray(context, obj));
                    return 1;
                }
                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_IS_FUNCTION: {
                if (argc == 1 && arguments[0].type == ARG_TYPE_MANAGED_VALUE) {
                    JSValue obj = JS_MKPTR(JS_TAG_OBJECT, arguments[0].ptrValue);
                    results[0].set((bool)JS_IsFunction(context, obj));
                    return 1;
                }
                results[0].set("WrongArguments");
                return -1;
            }
            case JS_ACTION_IS_CONSTRUCTOR: {
                if (argc == 1 && arguments[0].type == ARG_TYPE_MANAGED_VALUE) {
                    JSValue obj = JS_MKPTR(JS_TAG_OBJECT, arguments[0].ptrValue);
                    results[0].set((bool)JS_IsConstructor(context, obj));
                    return 1;
                }
                results[0].set("WrongArguments");
                return -1;
            }
        }
        results[0].set("NotImplement");
        return -1;
    }

    void clearCache() {
        for (auto it = temp_results.begin(), e = temp_results.end(); it != e; ++it) {
            JS_FreeValue(context, *it);
        }
        temp_results.clear();
    }

    JsArgument *retainValue(void *ptr) {
        JSValue value = JS_MKPTR(JS_TAG_OBJECT, ptr);
        if (JS_HasProperty(context, value, private_key)) {
            JS_DupValue(context, value);
            tempArgument.setDartObject(ptr);
        } else if (JS_HasProperty(context, value, class_private_key)) {
            JSValue key = JS_GetProperty(context, value, class_private_key);
            int id = JS_VALUE_GET_INT(key);
            JS_FreeValue(context, key);
            JS_DupValue(context, value);
            tempArgument.setDartClass(id, JS_VALUE_GET_PTR(value));
        } else {
            JS_DupValue(context, value);
            tempArgument.type = ARG_TYPE_MANAGED_VALUE;
            tempArgument.ptrValue = JS_VALUE_GET_PTR(value);
        }
        return &tempArgument;
    }

    void* registerClass(JsClass *clazz, int id) {
        JSClassID classId = 0;
        classId = JS_NewClassID(&classId);
        JSClassDef def = {
                .class_name = clazz->name,
                .finalizer = class_finalizer,
        };
        JS_NewClass(runtime, classId, &def);

        JSValue proto = JS_NewObject(context);
        JSValue thisData = JS_NewInt32(context, id);

        JSValue cons = JS_NewCFunctionMagic(
                context, constructor, clazz->name, 0, JS_CFUNC_constructor_magic, classId);

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
                JSAtom atom = JS_NewAtom(context, member.name);
                if (member.isStatic()) {
                    JSValue func = JS_NewCFunctionData(
                            context,
                            static_call,
                            0, i,
                            1, &thisData);
                    JS_SetProperty(
                            context, cons,
                            atom, func);
                } else {
                    JSValue func = JS_NewCFunctionData(
                            context,
                            member_call,
                            0, i,
                            1, &thisData);
                    JS_SetProperty(
                            context, proto,
                            atom, func);
                }
                JS_FreeAtom(context, atom);
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
        for (auto it = fields.begin(); it != fields.end(); ++it) {
            string name = it->first;
            const Field &field = it->second;
            JSAtom atom = JS_NewAtom(context, name.c_str());
            if (field.isStatic) {
                JSValue getter = field.getter == 0 ? JS_UNDEFINED :
                        JS_NewCFunctionData(context,
                                            static_getter,
                                            0, field.getter,
                                            1, &thisData);
                JSValue setter = field.setter == 0 ? JS_UNDEFINED :
                        JS_NewCFunctionData(context,
                                            static_setter,
                                            1, field.setter,
                                            1, &thisData);

                JS_DefinePropertyGetSet(
                        context,
                        cons, atom,
                        getter,
                        setter,
                        0);
            } else {
                JSValue getter = field.getter == 0 ? JS_UNDEFINED :
                        JS_NewCFunctionData(context,
                                            field_getter,
                                            0, field.getter,
                                            1, &thisData);
                JSValue setter = field.setter == 0 ? JS_UNDEFINED :
                        JS_NewCFunctionData(context,
                                            field_setter,
                                            1, field.setter,
                                            1, &thisData);
                JS_DefinePropertyGetSet(
                        context,
                        proto, atom,
                        getter,
                        setter,
                        0);
            }
            JS_FreeAtom(context, atom);
        }

        JS_SetConstructor(context, cons, proto);
        JS_SetClassProto(context, classId, proto);

        JS_SetProperty(context, cons, class_private_key, JS_DupValue(context, thisData));

        JS_FreeValue(context, thisData);

        classVector.push_back(JS_DupValue(context, cons));

        JSValue global = JS_GetGlobalObject(context);
        JS_SetPropertyStr(context, global, clazz->name, cons);
        JS_FreeValue(context, global);

        return JS_VALUE_GET_PTR(cons);
    }

    JsPromise *newPromise() {
        JSValue ctor = JS_GetPromiseConstructor(context);
        JsPromise *pro = new JsPromise();
        JSValue data = JS_NewBigInt64(context, (int64_t)pro);
        JSValue func = JS_NewCFunctionData(context, promise_init, 2, 0, 1, &data);
        JS_FreeValue(context, data);

        JSValue value = JS_CallConstructor(context, ctor, 1, &func);
        JS_FreeValue(context, func);
        if (JS_IsException(value)) {
            JSValue ex = JS_GetException(context);
            temp_string = errorString(ex);
            results[0].set(temp_string.c_str());
            JS_FreeValue(context, ex);
            pro->free(context);
            delete pro;
            return nullptr;
        } else {
            pro->target = value;
            return pro;
        }
    }

    static void print(JsContext *that, int type, const char *format, ...) {
        va_list vlist;
        char str[1024];
        va_start(vlist, format);
        vsnprintf(str, 1024, format, vlist);
        va_end(vlist);
        str[1023] = 0;
        if (that && that->handlers.print)
            that->handlers.print(type, str);
    }

    bool hasPendingJob() {
        return JS_IsJobPending(runtime);
    }

    int executePendingJob() {
        JSContext  *context;
        int ret = JS_ExecutePendingJob(runtime, &context);
        if (ret == -1) {
            JSValue ex = JS_GetException(context);
            temp_string = errorString(ex);
            results[0].set(temp_string.c_str());
            JS_FreeValue(context, ex);
        }
        return ret;
    }
};

JsContext *JsContext::_temp = nullptr;

extern "C" {


stringstream output;

extern void JS_Log(const char *format, ...) {
    if (JsContext::_temp) {
        va_list vlist;
        va_start(vlist, format);
        char str[256];
        vsnprintf(str, 256, format, vlist);
        va_end(vlist);
        str[255] = 0;

        string sstr = str;
        output << sstr;
        if (sstr.find('\n') >= 0) {
            string all = output.str();
            JsContext::print(JsContext::_temp, 0, "%s", all.c_str());
            stringstream temp;
            output.swap(temp);
        }
    }
}

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
    JSValue val = JS_MKPTR(JS_TAG_STRING, p);
    return JS_ToCString(that->context, val);
}

void jsContextFreeStringPtr(JsContext *that, const char * ptr) {
    JS_FreeCString(that->context, ptr);
}

JsArgument *jsContextRetainValue(JsContext *self, void *ptr) {
    return self->retainValue(ptr);
}

void jsContextReleaseValue(JsContext *self, void *ptr) {
    JSValue value = JS_MKPTR(JS_TAG_OBJECT, ptr);
    JSContext *context = self->context;
    JS_FreeValue(context, value);
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
    return self->hasPendingJob();
}

int jsContextExecutePendingJob(JsContext *self) {
    return self->executePendingJob();
}

void jsContextSetup() {}

}
