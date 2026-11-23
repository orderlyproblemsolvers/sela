import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_icons.dart';
import '../bible/bible_repository.dart';
import '../notes/note.dart';
import '../notes/note_io.dart';
import '../notes/note_store.dart';
import '../notes/settings_store.dart';
import '../tokens.dart';

/// Widest the settings list grows, so rows stay readable on tablets/desktop.
const double _maxContentWidth = 640;

Future<T?> _pick<T>(
  BuildContext context,
  String title,
  List<(T, String)> options,
  T current,
) {
  return showModalBottomSheet<T>(
    context: context,
    builder: (ctx) => SafeArea(
      // Scrollable so the sheet can't overflow with many options.
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
            child: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
          ),
          for (final (value, label) in options)
            ListTile(
              title: Text(label),
              trailing: value == current
                  ? Icon(AppIcons.check,
                      color: Theme.of(ctx).colorScheme.primary)
                  : null,
              onTap: () => Navigator.pop(ctx, value),
            ),
          const SizedBox(height: Space.sm),
        ],
      ),
    ),
  );
}

// ------------------------------------------------------------------ backup I/O

void _toast(ScaffoldMessengerState m, String message) => m
  ..clearSnackBars()
  ..showSnackBar(SnackBar(content: Text(message)));

/// Users get a plain message; the raw exception only shows in debug builds.
String _failure(String what, Object e) =>
    kDebugMode ? '$what: $e' : '$what. Please try again.';

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Serializes all notes to JSON.
/// Desktop: native Save dialog. Mobile: temp file + system share sheet.
Future<void> _exportNotes(BuildContext context, NoteStore notes) async {
  final messenger = ScaffoldMessenger.of(context);
  final data = notes.exportAll().map((n) => n.toJson()).toList();
  final jsonString = jsonEncode(data);
  final Uint8List bytes = utf8.encode(jsonString);

  try {
    if (_isDesktop) {
      final Uri? uri = await FilePicker.saveFile(
        dialogTitle: 'Save notes export',
        fileName: 'bible_notes_export.json',
        bytes: bytes,
        mimeType: 'application/json',
      );
      if (uri == null) return; // cancelled

      // Desktop returns a file:// URI without writing the bytes.
      if (uri.scheme == 'file') {
        await File(uri.toFilePath()).writeAsString(jsonString);
      }
      _toast(messenger, 'Exported ${data.length} notes.');
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/bible_notes_export.json');
      await file.writeAsString(jsonString);

      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'Bible Notes export',
        ),
      );
      if (result.status == ShareResultStatus.success) {
        _toast(messenger, 'Exported ${data.length} notes.');
      }
    }
  } catch (e) {
    _toast(messenger, _failure('Export failed', e));
  }
}

/// Picks a JSON backup, decodes it, and merges it into the store.
Future<void> _importNotes(BuildContext context, NoteStore notes) async {
  final messenger = ScaffoldMessenger.of(context);

  try {
    final result = await FilePicker.pickFile(
      dialogTitle: 'Pick a notes backup',
    );
    final path = result?.path;
    if (path == null) return; // cancelled

    final decoded = jsonDecode(await File(path).readAsString());
    if (decoded is! List) {
      _toast(messenger, 'That file isn’t a notes backup.');
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
    _toast(
      messenger,
      'Imported ${summary.added} new, updated ${summary.updated}$tail.',
    );
  } catch (e) {
    _toast(messenger, _failure('Import failed', e));
  }
}

/// Picks a Markdown (.md or .txt) file and saves it as a rich-text note.
Future<void> _importMarkdownNote(BuildContext context, NoteStore notes) async {
  final messenger = ScaffoldMessenger.of(context);

  try {
    final result = await FilePicker.pickFile(
      dialogTitle: 'Pick a Markdown (.md) file',
    );
    final path = result?.path;
    if (path == null) return; // cancelled

    final raw = await File(path).readAsString();
    final fileName = path
        .split(RegExp(r'[/\\]'))
        .last
        .replaceAll(RegExp(r'\.(md|markdown|txt)$', caseSensitive: false), '');

    final note = NoteIO.fromMarkdown(raw, fallbackTitle: fileName);
    await notes.save(note);

    _toast(messenger, 'Imported “${note.displayTitle}” from Markdown.');
  } catch (e) {
    _toast(messenger, _failure('Markdown import failed', e));
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
          final scalePct = (settings.editorScale * 100).round();

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxContentWidth),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    Space.lg, Space.xs, Space.lg, Space.xxl + Space.sm),
                children: [
                  // -------------------------------------------------- Appearance
                  const _GroupLabel('Appearance'),
                  _Group(children: [
                    Padding(
                      padding: const EdgeInsets.all(Space.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Theme', style: tt.titleMedium),
                          const SizedBox(height: Space.md),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<ThemeMode>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                  value: ThemeMode.system,
                                  icon: Icon(AppIcons.themeSystem),
                                  label: Text('System'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.light,
                                  icon: Icon(AppIcons.themeLight),
                                  label: Text('Light'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  icon: Icon(AppIcons.themeDark),
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
                      padding: const EdgeInsets.fromLTRB(
                          Space.lg, Space.lg, Space.lg, Space.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('Text size in notes',
                                    style: tt.titleMedium),
                              ),
                              Text(
                                '$scalePct%',
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
                            label: '$scalePct%',
                            semanticFormatterCallback: (v) =>
                                '${(v * 100).round()} percent',
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

                  // ---------------------------------------------------- Bible
                  const _GroupLabel('Bible'),
                  _Group(children: [
                    ListTile(
                      title: const Text('Default translation'),
                      subtitle: Text(
                        ids.isEmpty
                            ? 'No Bibles installed'
                            : (bibles.selectedId ?? ids.first),
                      ),
                      trailing: const Icon(AppIcons.chevronRight),
                      enabled: ids.isNotEmpty,
                      onTap: () async {
                        final v = await _pick<String>(
                          context,
                          'Default translation',
                          [
                            for (final id in ids)
                              (
                                id,
                                '$id · ${bibles.version(id)?.verses.length ?? 0} verses',
                              ),
                          ],
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
                  ]),

                  // ---------------------------------------------------- Notes
                  const _GroupLabel('Notes'),
                  _Group(children: [
                    ListTile(
                      title: const Text('Sort notes by'),
                      subtitle: Text(_sortLabels[settings.sort]!),
                      trailing: const Icon(AppIcons.chevronRight),
                      onTap: () async {
                        final v = await _pick<NoteSort>(
                          context,
                          'Sort notes by',
                          [
                            for (final e in _sortLabels.entries)
                              (e.key, e.value),
                          ],
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
                      trailing: const Icon(AppIcons.chevronRight),
                      onTap: () async {
                        final v = await _pick<int>(
                          context,
                          'Empty Trash automatically',
                          [
                            for (final d in const [7, 30, 90, 0])
                              (d, _trashLabel(d)),
                          ],
                          settings.trashDays,
                        );
                        if (v != null) {
                          await settings.setTrashDays(v);
                          unawaited(notes.purgeTrash(v));
                        }
                      },
                    ),
                  ]),

                  // --------------------------------------------------- Backup
                  const _GroupLabel('Backup'),
                  _Group(children: [
                    ListTile(
                      leading: const Icon(AppIcons.uploadFile),
                      title: const Text('Export notes…'),
                      subtitle: Text(
                        noteCount == 0
                            ? 'No notes to export yet'
                            : 'Save all $noteCount notes to a JSON file',
                      ),
                      trailing: const Icon(AppIcons.chevronRight),
                      enabled: noteCount > 0,
                      onTap: () => _exportNotes(context, notes),
                    ),
                    ListTile(
                      leading: const Icon(AppIcons.download),
                      title: const Text('Import notes…'),
                      subtitle:
                          const Text('Merge notes from a JSON backup file'),
                      trailing: const Icon(AppIcons.chevronRight),
                      onTap: () => _importNotes(context, notes),
                    ),
                    ListTile(
                      leading: const Icon(AppIcons.noteAdd),
                      title: const Text('Import Markdown file…'),
                      subtitle:
                          const Text('Create a note from a .md or .txt file'),
                      trailing: const Icon(AppIcons.chevronRight),
                      onTap: () => _importMarkdownNote(context, notes),
                    ),
                  ]),

                  // ---------------------------------------------------- About
                  const _GroupLabel('About'),
                  const _Group(children: [
                    ListTile(
                      leading: Icon(AppIcons.lock),
                      title: Text('Everything stays on this device'),
                      subtitle: Text(
                          'Notes and Bibles are stored locally. Nothing is sent over the network.'),
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Sentence-case group title, matching the section headers on the notes list.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Space.sm, Space.xl, Space.sm, Space.sm),
        child: Text(
          text,
          style: tt.titleSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
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
        borderRadius: BorderRadius.circular(Radii.lg),
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