#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint js_script.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'js_script'
  s.version          = '0.0.1'
  s.summary          = 'Run JS script.'
  s.description      = <<-DESC
Run JS script.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = [
    'Classes/quickjs/quickjs_ext.c',
    'Classes/quickjs/quickjs_dart.cpp',
    'Classes/quickjs/libbf.c',
    'Classes/quickjs/qjscalc.c',
    'Classes/quickjs/libregexp.c',
    'Classes/quickjs/libunicode.c',
    'Classes/quickjs/cutils.c',
    # Be free to test jscore code, but it is too slow than quickjs. 
    # 'Classes/jscore/jscore_dart.mm',
    'Classes/JsScriptPlugin.m',
    'Classes/JsScriptPlugin.h',
  ]
  s.public_header_files = 'Classes/JsScriptPlugin.h'
  s.dependency 'FlutterMacOS'
  s.library = 'c++'
  s.framework = 'JavaScriptCore'
  s.platform = :osx, '10.9'
  s.requires_arc = false
  s.compiler_flags = '-DCONFIG_VERSION=\"qjs_dart\" -DEMSCRIPTEN -DDUMP_LEAKS -DCONFIG_BIGNUM'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
