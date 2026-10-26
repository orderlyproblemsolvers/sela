import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'note.dart';

/// Stores notes on the device (shared_preferences). No network involved.
class NoteStore extends ChangeNotifier {
  static const _idsKey = 'note_ids';

  late final SharedPreferences _prefs;
  final List<Note> _notes = [];

  List<Note> get notes => List.unmodifiable(_notes);

  bool contains(String id) => _notes.any((n) => n.id == id);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final ids = _prefs.getStringList(_idsKey) ?? const <String>[];
    for (final id in ids) {
      final raw = _prefs.getString('note:$id');
      if (raw == null) continue;
      try {
        _notes.add(Note.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // skip a corrupt note rather than crash
      }
    }
  }

  Note newNote() => Note(id: DateTime.now().microsecondsSinceEpoch.toString());

  Future<void> _persist(Note n) =>
      _prefs.setString('note:${n.id}', jsonEncode(n.toJson()));

  Future<void> _persistIds() =>
      _prefs.setStringList(_idsKey, _notes.map((n) => n.id).toList());

  /// Adds or updates a single note.
  Future<void> save(Note note) async {
    if (!contains(note.id)) _notes.add(note);
    await _persist(note);
    await _persistIds();
    notifyListeners();
  }

  Future<void> _batch(Iterable<Note> targets, void Function(Note) change) async {
    final list = targets.toList();
    for (final n in list) {
      change(n);
    }
    notifyListeners();
    for (final n in list) {
      await _persist(n);
    }
  }

  Future<void> setPinned(Iterable<Note> targets, bool value) =>
      _batch(targets, (n) => n.pinned = value);

  /// Archiving also unpins.
  Future<void> setArchived(Iterable<Note> targets, bool value) =>
      _batch(targets, (n) {
        n.archived = value;
        if (value) n.pinned = false;
      });

  /// Soft delete: moves to the trash.
  Future<void> trash(Iterable<Note> targets) => _batch(targets, (n) {
        n.deletedAt = DateTime.now();
        n.pinned = false;
      });

  Future<void> restore(Iterable<Note> targets) =>
      _batch(targets, (n) => n.deletedAt = null);

  Future<void> deleteForever(Iterable<Note> targets) async {
    final ids = targets.map((n) => n.id).toSet();
    _notes.removeWhere((n) => ids.contains(n.id));
    notifyListeners();
    for (final id in ids) {
      await _prefs.remove('note:$id');
    }
    await _persistIds();
  }

  Future<void> emptyTrash() =>
      deleteForever(_notes.where((n) => n.isTrashed).toList());

  /// Permanently removes notes that have been in the trash for [days] days.
  Future<void> purgeTrash(int days) async {
    if (days <= 0) return;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final old = _notes
        .where((n) => n.deletedAt != null && n.deletedAt!.isBefore(cutoff))
        .toList();
    if (old.isNotEmpty) await deleteForever(old);
  }

  // ------------------------------------------------------------ export/import

  /// A snapshot of every note, suitable for encoding as JSON and saving to a
  /// file. The caller does the file I/O (file_picker / share_plus) so this
  /// store stays platform-agnostic.
  List<Note> exportAll() => List<Note>.from(_notes);

  /// Merges the given notes into the store: notes whose id already exists are
  /// updated in place, new ones are added. Returns how many were added and
  /// how many were updated.
  Future<({int added, int updated})> importFrom(List<Note> incoming) async {
    var added = 0;
    var updated = 0;

    for (final incomingNote in incoming) {
      final index = _notes.indexWhere((n) => n.id == incomingNote.id);
      if (index >= 0) {
        // Update the existing instance in place so any live references
        // (e.g. an open editor) see the new content.
        final existing = _notes[index];
        existing.title = incomingNote.title;
        existing.preview = incomingNote.preview;
        existing.plain = incomingNote.plain;
        existing.pinned = incomingNote.pinned;
        existing.archived = incomingNote.archived;
        existing.deletedAt = incomingNote.deletedAt;
        existing.delta = incomingNote.delta;
        existing.updatedAt = incomingNote.updatedAt;
        // createdAt is final on Note, so it can't be reassigned. The
        // existing note keeps its original creation time, which is the
        // desired "merge" semantics.
        await _persist(existing);
        updated++;
      } else {
        _notes.add(incomingNote);
        await _persist(incomingNote);
        added++;
      }
    }

    if (added > 0) {
      await _persistIds();
    }
    if (added > 0 || updated > 0) {
      notifyListeners();
    }
    return (added: added, updated: updated);
  }
}