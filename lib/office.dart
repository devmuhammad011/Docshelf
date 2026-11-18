import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class PreviewPart {
  const PreviewPart(this.title, {this.blocks = const [], this.rows = const []});
  final String title;
  final List<Object> blocks;
  final List<List<String>> rows;
}

Iterable<XmlElement> elements(XmlNode node, String name) =>
    node.descendants.whereType<XmlElement>().where((e) => e.name.local == name);

String textRuns(XmlNode node) =>
    elements(node, 't').map((e) => e.innerText).join();

List<PreviewPart> readOffice(Uint8List bytes, String extension) {
  final archive = ZipDecoder().decodeBytes(bytes);
  var expandedSize = 0;
  for (final entry in archive.files) {
    expandedSize += entry.size;
    if (expandedSize > 128 * 1024 * 1024) {
      throw const FormatException('The expanded document is too large');
    }
  }
  final files = {for (final entry in archive.files) entry.name: entry};
  XmlDocument xml(String path) =>
      XmlDocument.parse(utf8.decode(files[path]!.content));

  Map<String, String> relationships(String path) {
    if (!files.containsKey(path)) return {};
    return {
      for (final entry in elements(xml(path), 'Relationship'))
        if (entry.getAttribute('TargetMode') != 'External')
          entry.getAttribute('Id')!: entry.getAttribute('Target')!,
    };
  }

  String? target(String folder, String? path) => path == null
      ? null
      : Uri.parse('/$folder/').resolve(path).path.substring(1);

  String? relationshipId(XmlElement element, String local) {
    for (final attr in element.attributes) {
      if (attr.name.local == local && attr.name.prefix != null) {
        return attr.value;
      }
    }
    return null;
  }

  List<Object> slideBlocks(String path) {
    final slash = path.lastIndexOf('/');
    final folder = path.substring(0, slash);
    final name = path.substring(slash + 1);
    final links = relationships('$folder/_rels/$name.rels');
    final blocks = <Object>[];
    for (final node in xml(path).descendants.whereType<XmlElement>()) {
      if (node.name.local == 'p') {
        final text = textRuns(node);
        if (text.trim().isNotEmpty) blocks.add(text);
      } else if (node.name.local == 'blip') {
        final imagePath = target(folder, links[relationshipId(node, 'embed')]);
        final content = files[imagePath]?.content;
        if (content != null) blocks.add(Uint8List.fromList(content));
      }
    }
    return blocks;
  }

  switch (extension) {
    case 'docx':
      final links = relationships('word/_rels/document.xml.rels');
      final body = elements(xml('word/document.xml'), 'body').first;
      final blocks = <Object>[];
      for (final node in body.childElements) {
        if (node.name.local == 'tbl') {
          blocks.add([
            for (final row in elements(node, 'tr'))
              [
                for (final cell in row.childElements.where(
                  (e) => e.name.local == 'tc',
                ))
                  elements(cell, 'p').map(textRuns).join('\n'),
              ],
          ]);
        } else if (node.name.local == 'p') {
          final paragraph = textRuns(node);
          if (paragraph.trim().isNotEmpty) blocks.add(paragraph);
          for (final image in elements(node, 'blip')) {
            final path = target('word', links[relationshipId(image, 'embed')]);
            final content = files[path]?.content;
            if (content != null) blocks.add(Uint8List.fromList(content));
          }
        }
      }
      return [PreviewPart('Document', blocks: blocks)];
    case 'xlsx':
      final links = relationships('xl/_rels/workbook.xml.rels');
      final strings = files.containsKey('xl/sharedStrings.xml')
          ? elements(xml('xl/sharedStrings.xml'), 'si').map(textRuns).toList()
          : <String>[];
      return [
        for (final sheet in elements(xml('xl/workbook.xml'), 'sheet'))
          if (target('xl', links[relationshipId(sheet, 'id')])
              case final String path)
            PreviewPart(
              sheet.getAttribute('name') ?? 'Sheet',
              rows: [
                for (final row in elements(xml(path), 'row'))
                  _sheetRow(row, strings),
              ],
            ),
      ];
    case 'pptx':
      final links = relationships('ppt/_rels/presentation.xml.rels');
      final slides = elements(xml('ppt/presentation.xml'), 'sldId').toList();
      return [
        for (var index = 0; index < slides.length; index++)
          if (target('ppt', links[relationshipId(slides[index], 'id')])
              case final String path)
            PreviewPart('Slide ${index + 1}', blocks: slideBlocks(path)),
      ];
    default:
      throw const FormatException('Unsupported Office format');
  }
}

List<String> _sheetRow(XmlElement row, List<String> strings) {
  final values = <String>[];
  for (final cell in row.childElements.where((e) => e.name.local == 'c')) {
    final reference = cell.getAttribute('r') ?? '';
    final letters = RegExp(r'^[A-Z]+').stringMatch(reference);
    if (letters != null) {
      var column = 0;
      for (final char in letters.codeUnits) {
        column = column * 26 + char - 64;
      }
      while (values.length < column - 1 && values.length < 16384) {
        values.add('');
      }
    }
    final raw = elements(cell, 'v').firstOrNull?.innerText ?? '';
    final index = int.tryParse(raw);
    values.add(switch (cell.getAttribute('t')) {
      'inlineStr' => textRuns(cell),
      's' when index != null && index >= 0 && index < strings.length =>
        strings[index],
      'b' => raw == '1' ? 'TRUE' : 'FALSE',
      _ => raw,
    });
  }
  return values;
}
