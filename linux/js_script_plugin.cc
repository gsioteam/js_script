#include "include/js_script/js_script_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <cstring>
#include "quickjs/quickjs_ext.h"

#define JS_SCRIPT_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), js_script_plugin_get_type(), \
                              JsScriptPlugin))

struct _JsScriptPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(JsScriptPlugin, js_script_plugin, g_object_get_type())

// Called when a method call is received from Flutter.
static void js_script_plugin_handle_method_call(
    JsScriptPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  // const gchar* method = fl_method_call_get_name(method_call);
  response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

static void js_script_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(js_script_plugin_parent_class)->dispose(object);
}

static void js_script_plugin_class_init(JsScriptPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = js_script_plugin_dispose;
}

static void js_script_plugin_init(JsScriptPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  JsScriptPlugin* plugin = JS_SCRIPT_PLUGIN(user_data);
  js_script_plugin_handle_method_call(plugin, method_call);
}

void js_script_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  JsScriptPlugin* plugin = JS_SCRIPT_PLUGIN(
      g_object_new(js_script_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "js_script",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
  jsContextSetup();
}
