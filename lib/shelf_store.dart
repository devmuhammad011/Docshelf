import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

class ShelfStore {
  ShelfStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;
  static const recentLimit = 20;
  static const maxFileSize = 100 * 1024 * 1024;

  Future<Map<String, dynamic>> load() async {
    final file = File('${(await _directory()).path}/settings.json');
    if (!await file.exists()) return {};
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  Future<void> save(Map<String, dynamic> data) async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final temporary = File('${directory.path}/settings.new');
    await temporary.writeAsString(jsonEncode(data), flush: true);
    await temporary.rename('${directory.path}/settings.json');
  }

  Future<PlatformFile> retain(PlatformFile file) async {
    final source = File(file.path!);
    final size = await source.length();
    if (size > maxFileSize) throw const FormatException('File exceeds 100 MB');
    final root = Directory('${(await _directory()).path}/recent');
    if (source.parent.parent.path == root.path) return file;
    await root.create(recursive: true);
    final folder = await root.createTemp('document-');
    try {
      final name = file.name.split(RegExp(r'[/\\]')).last;
      if (name.isEmpty || name == '.' || name == '..') {
        throw const FormatException('Invalid file name');
      }
      final saved = await source.copy('${folder.path}/$name');
      return PlatformFile(name: name, size: size, path: saved.path);
    } catch (_) {
      await folder.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> removeCopies(Iterable<PlatformFile> removed) async {
    final root = Directory('${(await _directory()).path}/recent');
    if (!await root.exists()) return;
    for (final file in removed) {
      final folder = File(file.path!).parent;
      if (folder.parent.path == root.path && await folder.exists()) {
        await folder.delete(recursive: true);
      }
    }
  }
}
