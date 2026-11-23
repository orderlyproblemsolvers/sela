import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'note.dart';

/// Stores notes and folders on the device (shared_preferences). No network involved.
class NoteStore extends ChangeNotifier {
  static const _idsKey = 'note_ids';
  static const _foldersKey = 'note_folders';

  late final SharedPreferences _prefs;
  final List<Note> _notes = [];
  final List<NoteFolder> _folders = [];

  List<Note> get notes => List.unmodifiable(_notes);

  /// Active (non-trashed) folders.
  List<NoteFolder> get folders =>
      List.unmodifiable(_folders.where((f) => !f.isTrashed));

  /// Folders currently in Trash.
  List<NoteFolder> get trashedFolders =>
      List.unmodifiable(_folders.where((f) => f.isTrashed));

  /// All unique #tags across non-trashed notes, sorted alphabetically.
  List<String> get allTags {
    final set = <String>{};
    for (final n in _notes) {
      if (!n.isTrashed) set.addAll(n.tags);
    }
    return set.toList()..sort();
  }

  bool contains(String id) => _notes.any((n) => n.id == id);

  NoteFolder? folderById(String? id) {
    if (id == null) return null;
    for (final f in _folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Counts active (non-archived, non-trashed) notes inside [folderId].
  int noteCountInFolder(String folderId) => _notes
      .where((n) => !n.archived && !n.isTrashed && n.folderId == folderId)
      .length;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    final rawFolders = _prefs.getString(_foldersKey);
    if (rawFolders != null) {
      try {
        final decoded = jsonDecode(rawFolders) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            _folders.add(NoteFolder.fromJson(item));
          }
        }
      } catch (_) {
        // skip corrupt folder data rather than crash
      }
    }

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

  Note newNote({String? folderId}) => Note(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        folderId: folderId,
      );

  Future<void> _persist(Note n) =>
      _prefs.setString('note:${n.id}', jsonEncode(n.toJson()));

  Future<void> _persistIds() =>
      _prefs.setStringList(_idsKey, _notes.map((n) => n.id).toList());

  Future<void> _persistFolders() => _prefs.setString(
        _foldersKey,
        jsonEncode(_folders.map((f) => f.toJson()).toList()),
      );

  int _nextPinOrder() =>
      _notes
          .where((n) => n.pinned)
          .fold<int>(0, (prev, e) => e.pinOrder > prev ? e.pinOrder : prev) +
      1;

  // ------------------------------------------------------------------ folders

  Future<NoteFolder> createFolder(String name) async {
    final trimmed = name.trim();
    final folder = NoteFolder(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: trimmed.isEmpty ? 'Untitled folder' : trimmed,
    );
    _folders.add(folder);
    await _persistFolders();
    notifyListeners();
    return folder;
  }

  Future<void> renameFolder(String id, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final folder = folderById(id);
    if (folder == null) return;
    folder.name = trimmed;
    await _persistFolders();
    notifyListeners();
  }

  /// Moves the folder to Trash.
  /// If [trashNotes] is true, active notes inside it are also moved to Trash
  /// (keeping their folderId so restoring the folder restores them too).
  /// If [trashNotes] is false, notes inside it are moved back to the main list.
  Future<void> trashFolder(String id, {required bool trashNotes}) async {
    final folder = folderById(id);
    if (folder == null) return;

    final now = DateTime.now();
    folder.deletedAt = now;

    final affected =
        _notes.where((n) => n.folderId == id && !n.isTrashed).toList();
    for (final n in affected) {
      if (trashNotes) {
        n.deletedAt = now;
        n.pinned = false;
      } else {
        n.folderId = null;
      }
    }

    notifyListeners();
    await _persistFolders();
    for (final n in affected) {
      await _persist(n);
    }
  }

  /// Restores a folder from Trash (and any trashed notes that belonged to it).
  Future<void> restoreFolder(String id) async {
    final folder = folderById(id);
    if (folder == null) return;
    folder.deletedAt = null;

    final affected =
        _notes.where((n) => n.folderId == id && n.isTrashed).toList();
    for (final n in affected) {
      n.deletedAt = null;
    }

    notifyListeners();
    await _persistFolders();
    for (final n in affected) {
      await _persist(n);
    }
  }

  /// Permanently deletes a folder and any trashed notes still linked to it.
  Future<void> deleteFolderForever(String id) async {
    _folders.removeWhere((f) => f.id == id);

    final trashedInFolder =
        _notes.where((n) => n.folderId == id && n.isTrashed).toList();
    final activeInFolder =
        _notes.where((n) => n.folderId == id && !n.isTrashed).toList();

    for (final n in activeInFolder) {
      n.folderId = null;
      await _persist(n);
    }
    if (trashedInFolder.isNotEmpty) {
      await deleteForever(trashedInFolder);
    }

    await _persistFolders();
    notifyListeners();
  }

  /// Moves [targets] into [folderId] (or pass `null` to move back to root).
  Future<void> moveToFolder(Iterable<Note> targets, String? folderId) =>
      _batch(targets, (n) => n.folderId = folderId);

  // -------------------------------------------------------------------- notes

  /// Adds or updates a single note.
  Future<void> save(Note note) async {
    if (note.pinned && note.pinOrder == 0) {
      note.pinOrder = _nextPinOrder();
    }
    note.refreshTags();
    if (!contains(note.id)) _notes.add(note);
    await _persist(note);
    await _persistIds();
    notifyListeners();
  }

  Future<void> _batch(
      Iterable<Note> targets, void Function(Note) change) async {
    final list = targets.toList();
    for (final n in list) {
      change(n);
    }
    notifyListeners();
    for (final n in list) {
      await _persist(n);
    }
  }

  Future<void> setPinned(Iterable<Note> targets, bool value) {
    var maxOrder = _notes
        .where((n) => n.pinned)
        .fold<int>(0, (prev, e) => e.pinOrder > prev ? e.pinOrder : prev);
    return _batch(targets, (n) {
      n.pinned = value;
      if (value) {
        n.archived = false;
        n.pinOrder = ++maxOrder;
      }
    });
  }

  /// Moves a pinned note earlier (-1) or later (+1) in the pinned order.
  Future<void> movePinned(
    Note note,
    int deltaIndex,
    List<Note> currentPinned,
  ) async {
    final idx = currentPinned.indexOf(note);
    final targetIdx = idx + deltaIndex;
    if (idx < 0 || targetIdx < 0 || targetIdx >= currentPinned.length) return;

    final list = List<Note>.from(currentPinned);
    final item = list.removeAt(idx);
    list.insert(targetIdx, item);

    for (var i = 0; i < list.length; i++) {
      list[i].pinOrder = i + 1;
      await _persist(list[i]);
    }
    notifyListeners();
  }

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

  Future<void> emptyTrash() async {
    _folders.removeWhere((f) => f.isTrashed);
    await _persistFolders();
    await deleteForever(_notes.where((n) => n.isTrashed).toList());
  }

  /// Permanently removes folders and notes that have been in the trash for [days] days.
  Future<void> purgeTrash(int days) async {
    if (days <= 0) return;
    final cutoff = DateTime.now().subtract(Duration(days: days));

    final oldFolders = _folders
        .where((f) => f.deletedAt != null && f.deletedAt!.isBefore(cutoff))
        .map((f) => f.id)
        .toList();
    for (final id in oldFolders) {
      await deleteFolderForever(id);
    }

    final oldNotes = _notes
        .where((n) => n.deletedAt != null && n.deletedAt!.isBefore(cutoff))
        .toList();
    if (oldNotes.isNotEmpty) await deleteForever(oldNotes);
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
        final existing = _notes[index];
        existing.title = incomingNote.title;
        existing.preview = incomingNote.preview;
        existing.plain = incomingNote.plain;
        existing.pinned = incomingNote.pinned;
        existing.archived = incomingNote.archived;
        existing.pinOrder = incomingNote.pinOrder;
        existing.tags = incomingNote.tags;
        existing.folderId = incomingNote.folderId;
        existing.deletedAt = incomingNote.deletedAt;
        existing.delta = incomingNote.delta;
        existing.updatedAt = incomingNote.updatedAt;
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