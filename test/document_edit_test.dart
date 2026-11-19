import 'dart:io';

import 'package:archive/archive.dart';
import 'package:docshelf/document_edit.dart';
import 'package:docshelf/office.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (format, oldValue, replacement) in [
    ('docx', 'Takardar gwaji', 'Gyaran ƙarshe'),
    ('xlsx', '=1+2', '=2+3'),
    ('pptx', 'Ƙarshe', 'Ƙarin bayani'),
  ]) {
    test('edits a $format document while retaining its other parts', () {
      final source = File('test/fixtures/sample.$format');
      final original = source.readAsBytesSync();
      final sections = readEditableFile((source.path, format));
      final field = sections
          .expand((section) => section.fields)
          .singleWhere((field) => field.value == oldValue);
      final saved = saveEditedFile((
        source.path,
        format,
        {field.key: replacement},
      ));
      final updated = readOffice(saved, format);
      expect(
        updated.expand(
          (part) => [
            ...part.blocks.map(
              (block) => block is Heading ? block.text : block,
            ),
            ...part.rows.expand((row) => row),
          ],
        ),
        contains(replacement),
      );
      final previousArchive = ZipDecoder().decodeBytes(original);
      final newArchive = ZipDecoder().decodeBytes(saved);
      expect(
        newArchive.files.map((file) => file.name),
        unorderedEquals(previousArchive.files.map((file) => file.name)),
      );
      for (final previous in previousArchive.files) {
        if (previous.name != field.part &&
            !(format == 'xlsx' && previous.name == 'xl/workbook.xml') &&
            previous.isFile) {
          expect(newArchive.findFile(previous.name)!.content, previous.content);
        }
      }
      expect(source.readAsBytesSync(), original);
    });
  }

  test('rewrites text and CSV without altering the source', () {
    final directory = Directory.systemTemp.createTempSync('docshelf-edit');
    addTearDown(() => directory.deleteSync(recursive: true));
    for (final format in ['txt', 'csv']) {
      final file = File('${directory.path}/original.$format')
        ..writeAsStringSync('before');
      final field = readEditableFile((file.path, format)).single.fields.single;
      final output = saveEditedFile((
        file.path,
        format,
        {field.key: 'after,2'},
      ));
      expect(String.fromCharCodes(output), 'after,2');
      expect(file.readAsStringSync(), 'before');
    }
  });
}
