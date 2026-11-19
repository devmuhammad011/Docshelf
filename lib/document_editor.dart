import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'document_edit.dart';

class DocumentEditor extends StatefulWidget {
  const DocumentEditor({super.key, required this.file});

  final PlatformFile file;

  @override
  State<DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends State<DocumentEditor> {
  late final String format = widget.file.extension!.toLowerCase();
  late final Future<List<EditSection>> document = compute(readEditableFile, (
    widget.file.path!,
    format,
  ));
  final changes = <String, String>{};
  bool saving = false;
  int sectionIndex = 0;

  String nameForCopy() {
    final name = widget.file.name;
    return '${name.substring(0, name.lastIndexOf('.'))}-edited.$format';
  }

  void change(EditField field, String value) {
    setState(() {
      if (field.value == value) {
        changes.remove(field.key);
      } else {
        changes[field.key] = value;
      }
    });
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final bytes = await compute(saveEditedFile, (
        widget.file.path!,
        format,
        Map<String, String>.of(changes),
      ));
      if (!mounted) return;
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save edited document',
        fileName: nameForCopy(),
        bytes: bytes,
      );
      if (!mounted || destination == null) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Edited copy saved.')));
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn’t save. Your edits are still here.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> confirmExit(bool didPop, Object? _) async {
    if (didPop || saving || changes.isEmpty) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text('Use Save As to keep your edits in a new file.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (mounted && discard == true) Navigator.of(context).pop();
  }

  Future<void> editField(EditField field) async {
    var value = changes[field.key] ?? field.value;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(field.label),
        content: TextFormField(
          initialValue: value,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          inputFormatters: [
            if (format != 'xlsx')
              FilteringTextInputFormatter.singleLineFormatter,
          ],
          onChanged: (text) => value = text,
          decoration: const InputDecoration(labelText: 'Value'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) change(field, value);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving && changes.isEmpty,
    onPopInvokedWithResult: confirmExit,
    child: Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: saving ? () {} : () => Navigator.maybePop(context),
        ),
        title: const Text('Edit document'),
        actions: [
          TextButton.icon(
            onPressed: saving || changes.isEmpty ? null : save,
            icon: saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt_rounded),
            label: const Text('Save As'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<EditSection>>(
          future: document,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Text('This file couldn’t be opened for editing.'),
              );
            }
            final sections = snapshot.data;
            if (sections == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (sections.isEmpty) {
              return const Center(
                child: Text('There are no editable parts in this file.'),
              );
            }
            final section = sections[sectionIndex];
            final isPlain = format == 'txt' || format == 'csv';
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.file.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (isPlain)
                        Expanded(
                          child: TextFormField(
                            initialValue: section.fields.single.value,
                            expands: true,
                            minLines: null,
                            maxLines: null,
                            readOnly: saving,
                            keyboardType: TextInputType.multiline,
                            textAlignVertical: TextAlignVertical.top,
                            style: const TextStyle(fontFamily: 'monospace'),
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText: format == 'csv'
                                  ? 'CSV source'
                                  : 'Text',
                              alignLabelWithHint: true,
                            ),
                            onChanged: (value) =>
                                change(section.fields.single, value),
                          ),
                        )
                      else ...[
                        if (sections.length > 1)
                          DropdownMenu<int>(
                            expandedInsets: EdgeInsets.zero,
                            initialSelection: sectionIndex,
                            enabled: !saving,
                            label: Text(format == 'xlsx' ? 'Sheet' : 'Slide'),
                            onSelected: (value) {
                              if (value != null) {
                                setState(() => sectionIndex = value);
                              }
                            },
                            dropdownMenuEntries: [
                              for (final (index, item) in sections.indexed)
                                DropdownMenuEntry(
                                  value: index,
                                  label: item.title,
                                ),
                            ],
                          ),
                        if (section.fields.isEmpty)
                          const Expanded(
                            child: Center(
                              child: Text('No editable text or cells here.'),
                            ),
                          )
                        else
                          Expanded(
                            child: ListView.separated(
                              key: ValueKey(sectionIndex),
                              itemCount: section.fields.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final field = section.fields[index];
                                final value = changes[field.key] ?? field.value;
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  enabled: !saving,
                                  title: Text(
                                    value.isEmpty ? 'Empty' : value,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(field.label),
                                  trailing: const Icon(
                                    Icons.edit_outlined,
                                    size: 20,
                                  ),
                                  onTap: () => editField(field),
                                );
                              },
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
