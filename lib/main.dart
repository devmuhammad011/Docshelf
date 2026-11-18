import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import 'office.dart';

const navy = Color(0xff14213d);
const teal = Color(0xff2dd4bf);
const paper = Color(0xfff8fafc);
const slate = Color(0xff475569);
const formats = ['pdf', 'docx', 'xlsx', 'pptx', 'txt', 'csv'];

void main() => runApp(const DocShelfApp());

class DocShelfApp extends StatelessWidget {
  const DocShelfApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DocShelf',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: navy,
        surface: paper,
        onSurface: navy,
      ),
      scaffoldBackgroundColor: paper,
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: navy,
      ),
      useMaterial3: true,
    ),
    home: const Shelf(),
  );
}

class Shelf extends StatefulWidget {
  const Shelf({super.key});

  @override
  State<Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<Shelf> {
  final recent = <PlatformFile>[];
  bool opening = false;

  Future<void> open([PlatformFile? file]) async {
    if (opening) return;
    setState(() => opening = true);
    try {
      final selected =
          file ??
          (await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: formats,
          ))?.files.single;
      if (selected == null || !mounted) return;
      final path = selected.path;
      final extension = selected.extension?.toLowerCase();
      if (path == null || extension == null || !formats.contains(extension)) {
        throw const FormatException();
      }
      if (!await File(path).exists()) throw const FileSystemException();
      final preview = extension == 'pdf'
          ? null
          : await compute(loadPreview, (path, extension));
      if (!mounted) return;
      setState(() {
        recent.removeWhere((item) => item.path == path);
        recent.insert(0, selected);
      });
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => Reader(file: selected, preview: preview),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn’t open this file. Try choosing it again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                sliver: SliverList.list(
                  children: [
                    Row(
                      children: [
                        const BrandMark(),
                        const SizedBox(width: 12),
                        Text(
                          'DocShelf',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    Container(
                      padding: const EdgeInsets.all(26),
                      decoration: BoxDecoration(
                        color: navy,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Open a document',
                            style: TextStyle(
                              color: paper,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              height: 1.08,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Read PDFs, Word files, spreadsheets and slides on your device.',
                            style: TextStyle(
                              color: Color(0xffd1deed),
                              fontSize: 16,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: opening ? null : () => open(),
                            style: FilledButton.styleFrom(
                              backgroundColor: teal,
                              foregroundColor: navy,
                              disabledBackgroundColor: const Color(0xff31556a),
                              disabledForegroundColor: paper,
                              minimumSize: const Size(0, 52),
                            ),
                            icon: opening
                                ? const SizedBox.square(
                                    dimension: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: paper,
                                    ),
                                  )
                                : const Icon(Icons.folder_open_rounded),
                            label: Text(opening ? 'Opening…' : 'Browse files'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final format in formats)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: const Color(0xffdde5ee),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              format.toUpperCase(),
                              style: const TextStyle(
                                color: slate,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Recently opened',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    if (recent.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xffdde5ee)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.history_rounded, color: slate),
                            SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                'Files you open will appear here during this session.',
                                style: TextStyle(color: slate, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                sliver: SliverList.builder(
                  itemCount: recent.length,
                  itemBuilder: (context, index) {
                    final file = recent[index];
                    return Card(
                      color: Colors.white,
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        enabled: !opening,
                        onTap: () => open(file),
                        leading: const Icon(Icons.description_outlined),
                        title: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(file.extension?.toUpperCase() ?? ''),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(13),
    child: Image.asset('assets/docshelf.png', width: 46, height: 46),
  );
}

List<PreviewPart> loadPreview((String, String) file) {
  final bytes = File(file.$1).readAsBytesSync();
  switch (file.$2) {
    case 'txt':
      return [
        PreviewPart('Text', blocks: [utf8.decode(bytes, allowMalformed: true)]),
      ];
    case 'csv':
      final text = utf8.decode(bytes, allowMalformed: true);
      final rows = const CsvToListConverter(shouldParseNumbers: false)
          .convert(text, eol: text.contains('\r\n') ? '\r\n' : '\n');
      return [
        PreviewPart(
          'Table',
          rows: [
            for (final row in rows) [for (final cell in row) cell.toString()],
          ],
        ),
      ];
    default:
      return readOffice(bytes, file.$2);
  }
}

class Reader extends StatefulWidget {
  const Reader({super.key, required this.file, required this.preview});
  final PlatformFile file;
  final List<PreviewPart>? preview;

  @override
  State<Reader> createState() => _ReaderState();
}

class _ReaderState extends State<Reader> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final parts = widget.preview;
    final part = parts == null || parts.isEmpty ? null : parts[index];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.name, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        top: false,
        child: parts == null
            ? PdfViewer.file(
                widget.file.path!,
                params: PdfViewerParams(
                  errorBannerBuilder: (context, error, stack, document) =>
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('This PDF couldn’t be displayed.'),
                        ),
                      ),
                ),
              )
            : Column(
                children: [
                  if (parts.length > 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Previous',
                            onPressed: index > 0
                                ? () => setState(() => index--)
                                : null,
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Expanded(
                            child: Center(
                              child: DropdownMenu<int>(
                                key: ValueKey(index),
                                expandedInsets: EdgeInsets.zero,
                                initialSelection: index,
                                onSelected: (value) {
                                  if (value != null) {
                                    setState(() => index = value);
                                  }
                                },
                                dropdownMenuEntries: [
                                  for (var i = 0; i < parts.length; i++)
                                    DropdownMenuEntry(
                                      value: i,
                                      label: parts[i].title,
                                    ),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Next',
                            onPressed: index + 1 < parts.length
                                ? () => setState(() => index++)
                                : null,
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child:
                        part == null ||
                            (part.rows.isEmpty && part.blocks.isEmpty)
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'There is no readable content in this preview.',
                              ),
                            ),
                          )
                        : part.rows.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: TablePreview(
                              key: ValueKey(index),
                              rows: part.rows,
                            ),
                          )
                        : ListView.builder(
                            key: ValueKey(index),
                            padding: const EdgeInsets.all(20),
                            itemCount: part.blocks.length,
                            itemBuilder: (context, item) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: switch (part.blocks[item]) {
                                final Uint8List image => Image.memory(
                                  image,
                                  errorBuilder: (context, error, stack) =>
                                      const Text('Image unavailable'),
                                ),
                                final List<List<String>> rows => SizedBox(
                                  height: (rows.length * 44.0).clamp(
                                    44.0,
                                    264.0,
                                  ),
                                  child: TablePreview(rows: rows),
                                ),
                                final String text => SelectableText(
                                  text,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    height: 1.55,
                                  ),
                                ),
                                _ => const SizedBox.shrink(),
                              },
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

class TablePreview extends StatelessWidget {
  const TablePreview({super.key, required this.rows});
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final columns = rows.fold(
      0,
      (count, row) => row.length > count ? row.length : count,
    );
    return TableView.builder(
      rowCount: rows.length,
      columnCount: columns,
      diagonalDragBehavior: DiagonalDragBehavior.free,
      rowBuilder: (index) => const TableSpan(extent: FixedTableSpanExtent(44)),
      columnBuilder: (index) =>
          const TableSpan(extent: FixedTableSpanExtent(136)),
      cellBuilder: (context, vicinity) {
        final row = rows[vicinity.row];
        final value = vicinity.column < row.length ? row[vicinity.column] : '';
        return TableViewCell(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: vicinity.row.isEven
                  ? Colors.white
                  : const Color(0xffedf3f8),
              border: Border.all(color: const Color(0xffdce5ed), width: 0.5),
            ),
            child: SelectableText(value, maxLines: 1),
          ),
        );
      },
    );
  }
}
