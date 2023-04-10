
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:js_script/js_script.dart';
import 'package:path/path.dart' as path;

class IOFileSystem extends JsFileSystem {

  final Directory root;

  IOFileSystem(this.root, {
    String? mount
  }) : super(mount);

  @override
  bool exist(String filename) => File(path.join(root.path, filename)).existsSync();

  @override
  String? read(String filename) {
    try {
      return File(path.join(root.path, filename)).readAsStringSync();
    }catch (e) {
      return null;
    }
  }
}

class MemoryFileSystem extends JsFileSystem {
  final Map<String, String> memory;
  MemoryFileSystem(this.memory, {
    String? mount
  }) : super(mount);

  @override
  bool exist(String filename) => memory.containsKey(filename);

  @override
  String? read(String filename) => memory[filename];
}

class _FileIndex {
  String? link;
  int? size;
  int? offset;
}

class AsarFileSystem extends JsFileSystem {
  ByteData bytes;
  Map<String, _FileIndex> index = {};
  late int contentOffset;

  AsarFileSystem(this.bytes, {
    String? mount
  }) : super(mount) {
    int tag = bytes.getUint32(0, Endian.little);
    if (tag == 4) {
      int length = bytes.getInt32(4, Endian.little);
      tag = bytes.getInt32(8, Endian.little);
      if (tag + 4 == length) {
        int strlen = bytes.getInt32(12, Endian.little);
        if (strlen <= length) {
          var buf = bytes.buffer.asUint8List(bytes.offsetInBytes + 16, strlen);
          contentOffset = length + 8;
          var json = jsonDecode(utf8.decode(buf));
          _parseFile("", json);
        }
      } else {
        throw Exception("Can not parse Asar file");
      }
    } else {
      throw Exception("Can not parse Asar file");
    }
  }

  void _parseFile(String path, Map json) {
    if (json.containsKey("files")) {
      Map files = json["files"];
      for (var file in files.entries) {
        _parseFile("$path/${file.key}", file.value);
      }
    } else {
      _FileIndex fileIndex = _FileIndex();
      if (json.containsKey("link")) {
        fileIndex.link = json["link"];
      } else {
        int parseInt(input) {
          return (input is String) ? int.parse(input) : input;
        }
        fileIndex.offset = parseInt(json["offset"]);
        fileIndex.size = parseInt(json["size"]);
      }
      index[path] = fileIndex;
    }
  }

  @override
  bool exist(String filename) {
    return index.containsKey(filename);
  }

  @override
  String? read(String filename) {
    var fileIndex = index[filename];
    if (fileIndex != null) {
      if (fileIndex.link != null) {
        return read(fileIndex.link!);
      } else {
        return utf8.decode(bytes.buffer.asUint8List(
            fileIndex.offset! + contentOffset + bytes.offsetInBytes,
            fileIndex.size!));
      }
    }
    return null;
  }

}