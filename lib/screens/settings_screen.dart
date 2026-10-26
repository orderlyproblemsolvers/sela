import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../bible/bible_repository.dart';
import '../notes/note.dart';
import '../notes/note_store.dart';
import '../notes/settings_store.dart';

Future<T?> _pick<T>(
  BuildContext context,
  String title,
  List<(T, String)> options,
  T current,
) {
  return showModalBottomSheet<T>(
    context: context,
    builder: (ctx) => SafeArea(
      // Scrollable instead of a fixed Column, so the sheet can never
      // overflow when there are many options (e.g. 6+ Bible versions).
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
          ),
          for (final (value, label) in options)
            ListTile(
              title: Text(label),
              trailing: value == current
                  ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary)
                  : null,
              onTap: () => Navigator.pop(ctx, value),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

// ------------------------------------------------------------------ backup I/O

/// Serializes all notes to a JSON file.
///
/// On Windows: opens the native Save File dialog and writes the file.
/// On mobile: writes to a temp file and opens the system share sheet.
Future<void> _exportNotes(BuildContext context, NoteStore notes) async {
  final messenger = ScaffoldMessenger.of(context);
  final data = notes.exportAll().map((n) => n.toJson()).toList();
  final jsonString = jsonEncode(data);
  final Uint8List bytes = utf8.encode(jsonString);

  try {
    if (Platform.isWindows) {
      // New API: bytes + mimeType required; returns a Uri?
      final Uri? uri = await FilePicker.saveFile(
        dialogTitle: 'Save notes export',
        fileName: 'bible_notes_export.json',
        bytes: bytes,
        mimeType: 'application/json',
      );
      if (uri == null) return; // user cancelled

      // On desktop the plugin returns a file:// URI but does not write
      // the bytes; we write them ourselves.
      if (uri.scheme == 'file') {
        await File(uri.toFilePath()).writeAsString(jsonString);
      }
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('Exported ${data.length} notes.')),
        );
    } else {
      // Mobile: write to a temp file and open the system share sheet.
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/bible_notes_export.json');
      await file.writeAsString(jsonString);

      // share_plus 11+: instance-based API replaces Share.shareXFiles.
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'Bible Notes export',
        ),
      );

      if (result.status == ShareResultStatus.success) {
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text('Exported ${data.length} notes.')),
          );
      }
      // If the user dismissed the share sheet, do nothing (no snackbar).
    }
  } catch (e) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}

/// Picks a JSON file, decodes it into notes, and merges them into the store.
Future<void> _importNotes(BuildContext context, NoteStore notes) async {
  final messenger = ScaffoldMessenger.of(context);

  try {
    // New single-file API. If your file_picker version does not have
    // pickFile, use: final result = await FilePicker.pickFiles();
    final result = await FilePicker.pickFile(
      dialogTitle: 'Pick a notes backup',
    );
    final path = result?.path;
    if (path == null) return; // user cancelled

    final raw = await File(path).readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Import failed: not a notes file.')),
        );
      return;
    }

    final incoming = <Note>[];
    var skipped = 0;
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        try {
          incoming.add(Note.fromJson(item));
        } catch (_) {
          skipped++;
        }
      } else {
        skipped++;
      }
    }

    final summary = await notes.importFrom(incoming);
    final tail = skipped > 0 ? ' ($skipped skipped)' : '';
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${summary.added} new, '
            'updated ${summary.updated}$tail.',
          ),
        ),
      );
  } catch (e) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Import failed: $e')));
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.bibles,
    required this.notes,
  });

  final SettingsStore settings;
  final BibleRepository bibles;
  final NoteStore notes;

  static const _sortLabels = {
    NoteSort.edited: 'Last edited',
    NoteSort.created: 'Date created',
    NoteSort.title: 'Title (A–Z)',
  };

  String _trashLabel(int d) => d == 0 ? 'Never' : '$d days';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, bibles, notes]),
        builder: (context, _) {
          final ids = bibles.versionIds;
          final noteCount = notes.notes.length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              // ---------------------------------------------------- Appearance
              const _GroupLabel('Appearance'),
              _Group(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Theme', style: tt.titleMedium),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ThemeMode>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.brightness_auto_outlined),
                              label: Text('System'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode_outlined),
                              label: Text('Light'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode_outlined),
                              label: Text('Dark'),
                            ),
                          ],
                          selected: {settings.themeMode},
                          onSelectionChanged: (s) =>
                              settings.setThemeMode(s.first),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text('Text size in notes',
                                  style: tt.titleMedium)),
                          Text(
                            '${(settings.editorScale * 100).round()}%',
                            style: tt.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      Slider(
                        min: 0.85,
                        max: 1.5,
                        divisions: 13,
                        value: settings.editorScale,
                        onChanged: settings.setEditorScale,
                      ),
                      Text(
                        '“For God so loved the world…”',
                        style: TextStyle(
                          fontSize: 16 * settings.editorScale,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: const Text('Reduce motion'),
                  subtitle: const Text(
                      'Swaps sliding and zooming for simple fades. Also follows your system setting.'),
                  value: settings.reduceMotion,
                  onChanged: settings.setReduceMotion,
                ),
              ]),

              // ------------------------------------------------------- Bible
              const _GroupLabel('Bible'),
              _Group(children: [
                ListTile(
                  title: const Text('Default translation'),
                  subtitle: Text(
                    ids.isEmpty
                        ? 'No Bible files found in assets/bibles/'
                        : (bibles.selectedId ?? ids.first),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: ids.isNotEmpty,
                  onTap: () async {
                    final v = await _pick<String>(
                      context,
                      'Default translation',
                      [for (final id in ids) (id, id)],
                      bibles.selectedId ?? ids.first,
                    );
                    if (v != null) unawaited(bibles.select(v));
                  },
                ),
                SwitchListTile(
                  title: const Text('Auto-insert verses'),
                  subtitle: const Text(
                      'Typing “James 1:2 ” replaces it with the verse'),
                  value: settings.autoInsertVerses,
                  onChanged: settings.setAutoInsertVerses,
                ),
                SwitchListTile(
                  title: const Text('Insert verses expanded'),
                  subtitle: const Text(
                      'Off inserts just the reference; expand it later'),
                  value: settings.insertExpanded,
                  onChanged: settings.setInsertExpanded,
                ),
                for (final id in ids)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.menu_book_outlined,
                        size: 20, color: cs.onSurfaceVariant),
                    title: Text(id),
                    subtitle: Text(
                      '${bibles.version(id)?.verses.length ?? 0} verses'
                      '${id == bibles.selectedId ? '  ·  default' : ''}',
                    ),
                    onTap: () => unawaited(bibles.select(id)),
                  ),
              ]),

              // ------------------------------------------------------ Notes
              const _GroupLabel('Notes'),
              _Group(children: [
                ListTile(
                  title: const Text('Sort notes by'),
                  subtitle: Text(_sortLabels[settings.sort]!),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final v = await _pick<NoteSort>(
                      context,
                      'Sort notes by',
                      [for (final e in _sortLabels.entries) (e.key, e.value)],
                      settings.sort,
                    );
                    if (v != null) unawaited(settings.setSort(v));
                  },
                ),
                ListTile(
                  title: const Text('Empty Trash automatically'),
                  subtitle: Text(settings.trashDays == 0
                      ? 'Never'
                      : 'After ${settings.trashDays} days'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final v = await _pick<int>(
                      context,
                      'Empty Trash automatically',
                      [for (final d in const [7, 30, 90, 0]) (d, _trashLabel(d))],
                      settings.trashDays,
                    );
                    if (v != null) {
                      await settings.setTrashDays(v);
                      unawaited(notes.purgeTrash(v));
                    }
                  },
                ),
              ]),

              // ------------------------------------------------------ Backup
              const _GroupLabel('Backup'),
              _Group(children: [
                ListTile(
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('Export notes…'),
                  subtitle: Text(
                    noteCount == 0
                        ? 'No notes to export yet'
                        : 'Save all $noteCount notes to a JSON file',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: noteCount > 0,
                  onTap: () => _exportNotes(context, notes),
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Import notes…'),
                  subtitle:
                      const Text('Merge notes from a JSON backup file'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _importNotes(context, notes),
                ),
              ]),

              // ------------------------------------------------------ About
              const _GroupLabel('About'),
              const _Group(children: [
                ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Everything stays on this device'),
                  subtitle: Text(
                      'Notes and Bibles are stored locally. Nothing is sent over the network.'),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 22, 8, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ],
      ),
    );
  }
}