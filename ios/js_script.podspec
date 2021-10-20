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
    # This is jscore code, but it is too slow than quickjs. 
    # 'Classes/jscore/jscore_dart.mm',
    'Classes/JsScriptPlugin.h',
    'Classes/JsScriptPlugin.m',
  ]
  s.public_header_files = 'Classes/JsScriptPlugin.h'
  s.dependency 'Flutter'
  s.library = 'c++'
  s.framework = 'JavaScriptCore'
  s.platform = :ios, '8.0'
  s.requires_arc = false
  s.compiler_flags = '-DCONFIG_VERSION=\"qjs_dart\" -DEMSCRIPTEN -DDUMP_LEAKS -DCONFIG_BIGNUM'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
