import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docshelf/main.dart';
import 'package:docshelf/office.dart';
import 'package:docshelf/shelf_settings.dart';
import 'package:docshelf/shelf_store.dart';
import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  test(
    'retains documents and preferences, then clears only the app copy',
    () async {
      final folder = Directory.systemTemp.createTempSync('docshelf-history-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final original = File('${folder.path}/original.txt')
        ..writeAsStringSync('note');
      final store = ShelfStore(
        directory: () async => Directory('${folder.path}/app'),
      );
      final settings = ShelfSettings(store);
      addTearDown(settings.dispose);
      final file = await store.retain(
        PlatformFile(name: 'original.txt', size: 4, path: original.path),
      );
      await settings.remember(file);
      await Future.wait([
        settings.setTheme(ThemeMode.dark),
        settings.setTextSize(22),
      ]);
      final reopened = ShelfSettings(store);
      addTearDown(reopened.dispose);
      await reopened.restore();
      expect(reopened.theme, ThemeMode.dark);
      expect(reopened.textSize, 22);
      expect(reopened.recent.single.path, file.path);
      await reopened.clearHistory();
      expect(File(file.path!).existsSync(), isFalse);
      expect(original.readAsStringSync(), 'note');
      expect((await store.load())['recent'], isEmpty);
    },
  );

  testWidgets('opens Settings and changes the app theme', (tester) async {
    final folder = Directory.systemTemp.createTempSync('docshelf-settings-');
    addTearDown(() => folder.deleteSync(recursive: true));
    await tester.pumpWidget(
      DocShelfApp(store: ShelfStore(directory: () async => folder)),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Reading text size'), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });

  test('reads representative Word, Excel and PowerPoint files', () {
    List<PreviewPart> read(String format) => readOffice(
      File('test/fixtures/sample.$format').readAsBytesSync(),
      format,
    );
    final word = read('docx').single.blocks;
    expect((word.first as Heading).text, 'Takardar gwaji');
    expect(word[1], 'Layi na farko\nLayi na biyu');
    expect(word[2], isA<Uint8List>());
    expect(word[3], [
      ['Suna', 'Adadi'],
    ]);
    final sheets = read('xlsx');
    expect(sheets.map((part) => part.title), ['Summary', 'Details']);
    expect(sheets.first.rows, [
      [],
      [],
      ['', 'Jimilla', '=1+2'],
    ]);
    final slides = read('pptx');
    expect(slides.first.blocks[0], 'Rahoton wata');
    expect(slides.first.blocks[1], isA<Uint8List>());
    expect(slides.first.blocks[2], [
      ['Suna', 'Adadi'],
    ]);
    expect(slides.last.blocks.single, 'Ƙarshe');
  });

  test('PDF engine opens a local one-page document', () async {
    final folder = Directory.systemTemp.createTempSync('docshelf-pdf-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final file = File('${folder.path}/sample.pdf');
    final pdf = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[0];
    final objects = [
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] >>',
    ];
    for (final (index, object) in objects.indexed) {
      offsets.add(pdf.length);
      pdf.write('${index + 1} 0 obj\n$object\nendobj\n');
    }
    final xref = pdf.length;
    pdf.write('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
    for (final offset in offsets.skip(1)) {
      pdf.write("${offset.toString().padLeft(10, '0')} 00000 n \n");
    }
    pdf.write('trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
    file.writeAsStringSync(pdf.toString());
    await pdfrxInitialize();
    final doc = await PdfDocument.openFile(file.path);
    addTearDown(doc.dispose);
    expect(doc.pages, hasLength(1));
  });

  test('reads local text and quoted CSV cells', () {
    final folder = Directory.systemTemp.createTempSync('docshelf-test-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final text = File('${folder.path}/note.txt')
      ..writeAsStringSync('Sannu, ƙawata');
    final csv = File('${folder.path}/sheet.csv')
      ..writeAsStringSync('name,value\r\n"line, one",001');
    expect(loadPreview((text.path, 'txt')).single.blocks, ['Sannu, ƙawata']);
    expect(loadPreview((csv.path, 'csv')).single.rows, [
      ['name', 'value'],
      ['line, one', '001'],
    ]);
  });

  testWidgets('navigates between slide previews', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Reader(
          file: PlatformFile(name: 'demo.pptx', size: 10),
          preview: const [
            PreviewPart('Slide 1', blocks: ['First topic']),
            PreviewPart('Slide 2', blocks: ['Second topic']),
          ],
        ),
      ),
    );
    expect(find.text('First topic'), findsOneWidget);
    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Second topic'), findsOneWidget);
  });

  testWidgets('shows browse action and empty state at phone width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const DocShelfApp());
    expect(find.text('Browse files'), findsOneWidget);
    expect(find.text('Recently opened'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('DOCX preserves Unicode and table values', () {
    final bytes = ZipEncoder().encode(
      Archive()..addFile(
        ArchiveFile.string(
          'word/document.xml',
          '<document><body><p><r><t>Sannu da zuwa, ƙawata</t></r></p>'
              '<tbl><tr><tc><p><r><t>42</t></r></p></tc></tr></tbl></body></document>',
        ),
      ),
    );
    final result = readOffice(Uint8List.fromList(bytes), 'docx').single;
    expect(result.blocks.first, 'Sannu da zuwa, ƙawata');
    expect(result.blocks.last, [
      ['42'],
    ]);
  });

  test('XLSX resolves sheet links and preserves skipped columns', () {
    final bytes = ZipEncoder().encode(
      Archive()
        ..addFile(
          ArchiveFile.string(
            'xl/workbook.xml',
            '<workbook xmlns:r="urn:test"><sheets><sheet name="Totals" r:id="r1"/></sheets></workbook>',
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'xl/_rels/workbook.xml.rels',
            '<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/></Relationships>',
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'xl/worksheets/sheet1.xml',
            '<worksheet><sheetData><row r="1"><c r="B1"><v>42</v></c></row></sheetData></worksheet>',
          ),
        ),
    );
    final result = readOffice(Uint8List.fromList(bytes), 'xlsx').single;
    expect(result.title, 'Totals');
    expect(result.rows, [
      ['', '42'],
    ]);
  });

  test('PPTX follows presentation order', () {
    final bytes = ZipEncoder().encode(
      Archive()
        ..addFile(
          ArchiveFile.string(
            'ppt/presentation.xml',
            '<presentation xmlns:r="urn:test"><sldIdLst><sldId r:id="r2"/><sldId r:id="r1"/></sldIdLst></presentation>',
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'ppt/_rels/presentation.xml.rels',
            '<Relationships><Relationship Id="r1" Target="slides/slide1.xml"/>'
                '<Relationship Id="r2" Target="slides/slide2.xml"/></Relationships>',
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'ppt/slides/slide1.xml',
            '<slide><p><t>One</t></p></slide>',
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'ppt/slides/slide2.xml',
            '<slide><p><t>Two</t></p></slide>',
          ),
        ),
    );
    final result = readOffice(Uint8List.fromList(bytes), 'pptx');
    expect(result.map((slide) => slide.blocks.single), ['Two', 'One']);
  });
}
