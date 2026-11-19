import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'shelf_store.dart';

class ShelfSettings extends ChangeNotifier {
  ShelfSettings(this.store);

  final ShelfStore store;
  ThemeMode theme = ThemeMode.system;
  double textSize = 17;
  List<PlatformFile> recent = [];
  Future<void> _writes = Future.value();

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> restore() async {
    try {
      final data = await store.load();
      theme = ThemeMode.values.asNameMap()[data['theme']] ?? ThemeMode.system;
      final size = data['textSize'];
      if (size is num) textSize = size.toDouble().clamp(14, 24);
      final records = data['recent'];
      if (records is List) {
        for (final entry in records.take(ShelfStore.recentLimit)) {
          if (entry is! Map) continue;
          final path = entry['path'];
          final name = entry['name'];
          final size = entry['size'];
          if (path is String &&
              name is String &&
              size is int &&
              await File(path).exists()) {
            recent.add(PlatformFile(name: name, path: path, size: size));
          }
        }
      }
    } catch (_) {
      // A missing or unreadable settings file leaves the default library usable.
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setTheme(ThemeMode value) {
    theme = value;
    return _save();
  }

  Future<void> setTextSize(double value) {
    textSize = value;
    return _save();
  }

  Future<void> remember(PlatformFile file) {
    final previous = recent;
    recent = [
      file,
      ...recent.where((entry) => entry.path != file.path),
    ].take(ShelfStore.recentLimit).toList();
    return _save(
      removed: previous.where(
        (old) => !recent.any((item) => item.path == old.path),
      ),
    );
  }

  Future<void> clearHistory() {
    final previous = recent;
    recent = [];
    return _save(removed: previous);
  }

  Future<void> _save({Iterable<PlatformFile> removed = const []}) {
    final discarded = removed.toList();
    final retained = List<PlatformFile>.of(recent);
    final data = {
      'theme': theme.name,
      'textSize': textSize,
      'recent': [
        for (final file in retained)
          {'name': file.name, 'path': file.path, 'size': file.size},
      ],
    };
    final result = _writes.then((_) async {
      await store.save(data);
      await store.removeCopies(discarded);
    });
    _writes = result.catchError((Object _) {});
    notifyListeners();
    return result;
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage(this.settings, {super.key});

  final ShelfSettings settings;

  Future<void> save(BuildContext context, Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn’t save these settings.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListenableBuilder(
      listenable: settings,
      builder: (context, _) => SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final mode in ThemeMode.values)
                      ChoiceChip(
                        label: Text(switch (mode) {
                          ThemeMode.system => 'System',
                          ThemeMode.light => 'Light',
                          ThemeMode.dark => 'Dark',
                        }),
                        selected: settings.theme == mode,
                        onSelected: (_) =>
                            save(context, settings.setTheme(mode)),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  'Reading text size',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Slider(
                  value: settings.textSize,
                  min: 14,
                  max: 24,
                  divisions: 10,
                  label: settings.textSize.round().toString(),
                  onChanged: (value) =>
                      save(context, settings.setTextSize(value)),
                ),
                Text(
                  'This is how reading text will look.',
                  style: TextStyle(fontSize: settings.textSize),
                ),
                const SizedBox(height: 28),
                Text('History', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'Recent documents are kept as copies on this device.',
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Clear recent files'),
                    onPressed: settings.recent.isEmpty
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Clear recent files?'),
                                content: const Text(
                                  'This removes copies saved by DocShelf. Your original files will stay where they are.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Clear history'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true && context.mounted) {
                              await save(context, settings.clearHistory());
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
