#include "include/js_script/js_script_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>
#include <sstream>

namespace {

class JsScriptPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  JsScriptPlugin();

  virtual ~JsScriptPlugin();

 private:
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

// static
void JsScriptPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "js_script",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<JsScriptPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

JsScriptPlugin::JsScriptPlugin() {}

JsScriptPlugin::~JsScriptPlugin() {}

void JsScriptPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // if (method_call.method_name().compare("getPlatformVersion") == 0) {
  //   std::ostringstream version_stream;
  //   version_stream << "Windows ";
  //   if (IsWindows10OrGreater()) {
  //     version_stream << "10+";
  //   } else if (IsWindows8OrGreater()) {
  //     version_stream << "8";
  //   } else if (IsWindows7OrGreater()) {
  //     version_stream << "7";
  //   }
  //   result->Success(flutter::EncodableValue(version_stream.str()));
  // } else {
    result->NotImplemented();
  // }
}

}  // namespace

void JsScriptPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  JsScriptPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
