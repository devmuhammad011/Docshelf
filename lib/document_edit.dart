import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'office.dart';

const editableFormats = {'txt', 'csv', 'docx', 'xlsx', 'pptx'};

class EditField {
  const EditField(this.part, this.index, this.label, this.value);
  final String part;
  final int index;
  final String label;
  final String value;

  String get key => '$part#$index';
}

class EditSection {
  const EditSection(this.title, this.fields);
  final String title;
  final List<EditField> fields;
}

List<EditSection> readEditableFile((String, String) input) {
  final (path, format) = input;
  final bytes = File(path).readAsBytesSync();
  if (format == 'txt' || format == 'csv') {
    return [
      EditSection('Document', [
        EditField('', 0, 'Content', utf8.decode(bytes, allowMalformed: true)),
      ]),
    ];
  }
  final package = _OfficePackage(bytes, format);
  return [
    for (final (part, title) in package.parts())
      EditSection(title, [
        for (final (index, node) in package.nodes(part).indexed)
          EditField(
            part,
            index,
            format == 'xlsx'
                ? node.getAttribute('r') ?? 'Cell ${index + 1}'
                : 'Text ${index + 1}',
            package.value(node),
          ),
      ]),
  ];
}

Uint8List saveEditedFile((String, String, Map<String, String>) input) {
  final (path, format, changes) = input;
  final bytes = File(path).readAsBytesSync();
  if (changes.isEmpty) return bytes;
  if (format == 'txt' || format == 'csv') {
    final value = changes['#0'];
    return value == null ? bytes : utf8.encode(value);
  }
  if (changes.values.any(
    (value) => value.runes.any(
      (rune) =>
          rune < 32 && rune != 9 && rune != 10 && rune != 13 ||
          rune == 0xfffe ||
          rune == 0xffff,
    ),
  )) {
    throw const FormatException('The edit contains invalid XML characters');
  }
  final package = _OfficePackage(bytes, format);
  for (final (part, _) in package.parts()) {
    final document = package.xml(part);
    var modified = false;
    for (final (index, node) in package.nodes(part).indexed) {
      final value = changes['$part#$index'];
      if (value == null) continue;
      if (format == 'xlsx') {
        package.setCell(node, value);
      } else {
        node.children
          ..clear()
          ..add(XmlText(value));
        node.setAttribute('xml:space', 'preserve');
      }
      modified = true;
    }
    if (modified) {
      package.archive.addFile(ArchiveFile.string(part, document.toXmlString()));
    }
  }
  if (format == 'xlsx') package.refreshCalculation();
  return ZipEncoder().encodeBytes(package.archive);
}

class _OfficePackage {
  _OfficePackage(Uint8List bytes, this.format)
    : archive = ZipDecoder().decodeBytes(bytes) {
    var total = 0;
    for (final file in archive) {
      total += file.size;
      if (total > 128 * 1024 * 1024) {
        throw const FormatException('Expanded document is too large');
      }
    }
  }

  final Archive archive;
  final String format;
  final _documents = <String, XmlDocument>{};

  XmlDocument xml(String part) => _documents.putIfAbsent(
    part,
    () => XmlDocument.parse(utf8.decode(archive.findFile(part)!.content)),
  );

  Iterable<(String, String)> parts() sync* {
    if (format == 'docx') {
      yield ('word/document.xml', 'Document');
      return;
    }
    final sheet = format == 'xlsx';
    final root = sheet ? 'xl' : 'ppt';
    final main = sheet ? 'workbook.xml' : 'presentation.xml';
    final paths = {
      for (final node in elements(
        xml('$root/_rels/$main.rels'),
        'Relationship',
      ))
        if (node.getAttribute('TargetMode') != 'External' &&
            node.getAttribute('Id') != null &&
            node.getAttribute('Target') != null)
          node.getAttribute('Id')!: node.getAttribute('Target')!,
    };
    for (final (index, node) in elements(
      xml('$root/$main'),
      sheet ? 'sheet' : 'sldId',
    ).indexed) {
      final id = node.attributes
          .where(
            (attribute) =>
                attribute.name.local == 'id' && attribute.name.prefix != null,
          )
          .firstOrNull
          ?.value;
      final target = paths[id];
      if (target == null) continue;
      final uri = Uri.parse('/$root/').resolve(target);
      if (uri.hasScheme || uri.hasAuthority) continue;
      final part = uri.path.substring(1);
      if (archive.findFile(part) != null) {
        yield (
          part,
          sheet
              ? node.getAttribute('name') ?? 'Sheet ${index + 1}'
              : 'Slide ${index + 1}',
        );
      }
    }
  }

  Iterable<XmlElement> nodes(String part) {
    final document = xml(part);
    return format == 'xlsx'
        ? elements(document, 'c').where((cell) {
            final formula = elements(cell, 'f').firstOrNull;
            return formula == null ||
                formula.getAttribute('t') == null ||
                formula.getAttribute('t') == 'normal';
          })
        : elements(document, 't');
  }

  late final _sharedStrings = archive.findFile('xl/sharedStrings.xml') == null
      ? <String>[]
      : elements(xml('xl/sharedStrings.xml'), 'si').map(textRuns).toList();

  String value(XmlElement node) {
    if (format != 'xlsx') return node.innerText;
    final formula = elements(node, 'f').firstOrNull?.innerText;
    if (formula != null && formula.isNotEmpty) return '=$formula';
    final raw = elements(node, 'v').firstOrNull?.innerText ?? '';
    final index = int.tryParse(raw);
    return switch (node.getAttribute('t')) {
      'inlineStr' => textRuns(node),
      's' when index != null && index >= 0 && index < _sharedStrings.length =>
        _sharedStrings[index],
      'b' => raw == '1' ? 'TRUE' : 'FALSE',
      _ => raw,
    };
  }

  void refreshCalculation() {
    const workbookPath = 'xl/workbook.xml';
    const linksPath = 'xl/_rels/workbook.xml.rels';
    const contentPath = '[Content_Types].xml';
    final workbook = xml(workbookPath).rootElement;
    final calculation =
        workbook.childElements
            .where((node) => node.name.local == 'calcPr')
            .firstOrNull ??
        XmlElement(XmlName('calcPr', workbook.name.prefix));
    if (calculation.parent == null) {
      const following = {
        'oleSize',
        'customWorkbookViews',
        'pivotCaches',
        'smartTagPr',
        'smartTagTypes',
        'webPublishing',
        'fileRecoveryPr',
        'webPublishObjects',
        'extLst',
      };
      final index = workbook.children.indexWhere(
        (node) => node is XmlElement && following.contains(node.name.local),
      );
      workbook.children.insert(
        index < 0 ? workbook.children.length : index,
        calculation,
      );
    }
    calculation.setAttribute('fullCalcOnLoad', '1');
    archive.addFile(
      ArchiveFile.string(workbookPath, xml(workbookPath).toXmlString()),
    );

    final links = xml(linksPath);
    final chains = elements(links, 'Relationship')
        .where(
          (node) => node.getAttribute('Type')?.endsWith('/calcChain') ?? false,
        )
        .toList();
    if (chains.isEmpty) return;
    final content = xml(contentPath);
    for (final link in chains) {
      final target = link.getAttribute('Target');
      if (target != null) {
        final path = Uri.parse('/xl/').resolve(target).path;
        final file = archive.findFile(path.substring(1));
        if (file != null) archive.removeFile(file);
        content.rootElement.children.removeWhere(
          (node) => node is XmlElement && node.getAttribute('PartName') == path,
        );
      }
      link.parent!.children.remove(link);
    }
    archive.addFile(ArchiveFile.string(linksPath, links.toXmlString()));
    archive.addFile(ArchiveFile.string(contentPath, content.toXmlString()));
  }

  void setCell(XmlElement node, String value) {
    XmlElement element(String name, List<XmlNode> children) =>
        XmlElement(XmlName(name, node.name.prefix), [], children);

    node.children.removeWhere(
      (child) =>
          child is XmlElement && {'v', 'f', 'is'}.contains(child.name.local),
    );
    node.removeAttribute('t');
    if (value.isEmpty) return;
    final number = num.tryParse(value);
    final children = <XmlNode>[];
    if (value.startsWith('=') && value.length > 1) {
      children.add(element('f', [XmlText(value.substring(1))]));
    } else if (value == 'TRUE' || value == 'FALSE') {
      node.setAttribute('t', 'b');
      children.add(element('v', [XmlText(value == 'TRUE' ? '1' : '0')]));
    } else if (number != null &&
        number.isFinite &&
        RegExp(r'^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$')
            .hasMatch(value)) {
      children.add(element('v', [XmlText(value)]));
    } else {
      node.setAttribute('t', 'inlineStr');
      final text = element('t', [XmlText(value)])
        ..setAttribute('xml:space', 'preserve');
      children.add(element('is', [text]));
    }
    node.children.insertAll(0, children);
  }
}
