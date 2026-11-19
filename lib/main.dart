import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import 'document_edit.dart';
import 'document_editor.dart';
import 'office.dart';
import 'shelf_settings.dart';
import 'shelf_store.dart';

const navy = Color(0xff14213d);
const teal = Color(0xff2dd4bf);
const paper = Color(0xfff8fafc);
const slate = Color(0xff475569);
const formats = ['pdf', 'docx', 'xlsx', 'pptx', 'txt', 'csv'];

void main() => runApp(const DocShelfApp());

class DocShelfApp extends StatefulWidget {
  const DocShelfApp({super.key, this.store});
  final ShelfStore? store;

  @override
  State<DocShelfApp> createState() => _DocShelfAppState();
}

class _DocShelfAppState extends State<DocShelfApp> {
  late final settings = ShelfSettings(widget.store ?? ShelfStore());
  late final ready = settings.restore();

  @override
  void dispose() {
    settings.dispose();
    super.dispose();
  }

  ThemeData theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: brightness == Brightness.light ? navy : teal,
      brightness: brightness,
      surface: brightness == Brightness.light ? paper : const Color(0xff101827),
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
      ),
      useMaterial3: true,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => MaterialApp(
      title: 'DocShelf',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: settings.theme,
      home: Shelf(settings: settings, ready: ready),
    ),
  );
}

class Shelf extends StatefulWidget {
  const Shelf({super.key, required this.settings, required this.ready});
  final ShelfSettings settings;
  final Future<void> ready;

  @override
  State<Shelf> createState() => _ShelfState();
}

enum RecentAction { edit, share, saveCopy, remove }

class _ShelfState extends State<Shelf> {
  static const incoming = MethodChannel('docshelf/documents');
  ShelfSettings get settings => widget.settings;
  List<PlatformFile> get recent => settings.recent;
  bool draining = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      incoming.setMethodCallHandler((call) async {
        if (call.method == 'documentAvailable') unawaited(drainIncoming());
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(drainIncoming()),
      );
    }
  }

  @override
  void dispose() {
    if (Platform.isAndroid || Platform.isIOS) {
      incoming.setMethodCallHandler(null);
    }
    super.dispose();
  }

  void showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> drainIncoming() async {
    if (opening || managing || draining || !mounted) return;
    draining = true;
    try {
      while (mounted && !opening && !managing) {
        final data = await incoming.invokeMapMethod<String, dynamic>(
          'takeDocument',
        );
        if (data == null || !mounted) return;
        final error = data['error'];
        if (error is String) {
          showError(error);
          continue;
        }
        final path = data['path'] as String;
        try {
          await open(
            PlatformFile(
              name: data['name'] as String,
              size: data['size'] as int,
              path: path,
            ),
          );
        } finally {
          try {
            await File(path).delete();
          } on FileSystemException {
            // The import staging file may already have been removed by the OS.
          }
        }
      }
    } on MissingPluginException {
      // This platform has no external document handler.
    } finally {
      draining = false;
    }
  }

  bool opening = false;
  bool managing = false;

  Future<void> manage(PlatformFile file) async {
    if (opening || managing) return;
    setState(() => managing = true);
    try {
      final action = await showModalBottomSheet<RecentAction>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (editableFormats.contains(file.extension?.toLowerCase()))
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit'),
                    onTap: () => Navigator.pop(context, RecentAction.edit),
                  ),
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('Share'),
                  onTap: () => Navigator.pop(context, RecentAction.share),
                ),
                ListTile(
                  leading: const Icon(Icons.save_alt_rounded),
                  title: const Text('Save a copy'),
                  onTap: () => Navigator.pop(context, RecentAction.saveCopy),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Remove from recent'),
                  onTap: () => Navigator.pop(context, RecentAction.remove),
                ),
              ],
            ),
          ),
        ),
      );
      if (!mounted || action == null) return;
      switch (action) {
        case RecentAction.edit:
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => DocumentEditor(file: file)),
          );
        case RecentAction.share:
          final box = context.findRenderObject();
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(file.path!)],
              fileNameOverrides: [file.name],
              sharePositionOrigin: box is RenderBox && box.hasSize
                  ? box.localToGlobal(Offset.zero) & box.size
                  : null,
            ),
          );
        case RecentAction.saveCopy:
          final bytes = await File(file.path!).readAsBytes();
          if (!mounted) return;
          final saved = await FilePicker.platform.saveFile(
            dialogTitle: 'Save a copy',
            fileName: file.name,
            bytes: bytes,
          );
          if (mounted && saved != null) showError('Copy saved.');
        case RecentAction.remove:
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Remove from recent?'),
              content: const Text(
                'This removes the copy stored by DocShelf. Your original stays where it is.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Remove'),
                ),
              ],
            ),
          );
          if (mounted && confirmed == true) await settings.forget(file);
      }
    } catch (_) {
      if (mounted) showError('Couldn’t complete this file action.');
    } finally {
      if (mounted) {
        setState(() => managing = false);
        if (Platform.isAndroid || Platform.isIOS) unawaited(drainIncoming());
      }
    }
  }

  Future<void> open([PlatformFile? file]) async {
    if (opening || managing || (draining && file == null)) return;
    setState(() => opening = true);
    try {
      await widget.ready;
      if (!mounted) return;
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
      if (await File(path).length() > ShelfStore.maxFileSize) {
        if (mounted) showError('Choose a document under 100 MB.');
        return;
      }
      final preview = extension == 'pdf'
          ? null
          : await compute(loadPreview, (path, extension));
      if (!mounted) return;
      final retained = await settings.store.retain(selected);
      if (!mounted) return;
      await settings.remember(retained);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => Reader(
            file: retained,
            preview: preview,
            textSize: settings.textSize,
          ),
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
      if (mounted) {
        setState(() => opening = false);
        if (Platform.isAndroid || Platform.isIOS) unawaited(drainIncoming());
      }
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
                        const Spacer(),
                        IconButton(
                          tooltip: 'Settings',
                          onPressed: opening
                              ? null
                              : () async {
                                  await widget.ready;
                                  if (context.mounted && !opening) {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (context) =>
                                            SettingsPage(settings),
                                      ),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.settings_outlined),
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLow,
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              format.toUpperCase(),
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
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
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLow,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.history_rounded,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                'Files you open will appear here.',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  height: 1.4,
                                ),
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
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        enabled: !opening,
                        onTap: () => open(file),
                        onLongPress: opening ? null : () => manage(file),
                        leading: const Icon(Icons.description_outlined),
                        title: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(file.extension?.toUpperCase() ?? ''),
                        trailing: IconButton(
                          tooltip: 'File actions',
                          icon: const Icon(Icons.more_vert),
                          onPressed: opening || managing
                              ? null
                              : () => manage(file),
                        ),
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
  const Reader({
    super.key,
    required this.file,
    required this.preview,
    this.textSize = 17,
  });
  final PlatformFile file;
  final List<PreviewPart>? preview;
  final double textSize;

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
        actions: [
          if (widget.file.path != null &&
              editableFormats.contains(widget.file.extension?.toLowerCase()))
            IconButton(
              tooltip: 'Edit document',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DocumentEditor(file: widget.file),
                ),
              ),
            ),
        ],
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
                                final Heading heading => SelectableText(
                                  heading.text,
                                  style: TextStyle(
                                    fontSize: widget.textSize + 6,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                                ),
                                final String text => SelectableText(
                                  text,
                                  style: TextStyle(
                                    fontSize: widget.textSize,
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
                  ? Theme.of(context).colorScheme.surfaceContainerLowest
                  : Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
            child: SelectableText(value, maxLines: 1),
          ),
        );
      },
    );
  }
}
