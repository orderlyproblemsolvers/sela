import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bible_parser.dart';
import 'verse_ref.dart';

class BibleVersion {
  BibleVersion(this.id, this.verses);

  final String id;
  final Map<int, String> verses;

  String? verse(int book, int chapter, int verse) =>
      verses[verseKey(book, chapter, verse)];

  /// Searches this Bible version for verses containing all words in [query].
  List<(VerseRef, String)> search(String query, {int limit = 60}) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const [];

    final results = <(VerseRef, String)>[];
    for (final entry in verses.entries) {
      final text = entry.value;
      final lower = text.toLowerCase();
      if (words.every(lower.contains)) {
        final k = entry.key;
        final b = k ~/ 1000000;
        final c = (k % 1000000) ~/ 1000;
        final v = k % 1000;
        results.add((
          VerseRef(
            book: b,
            chapter: c,
            verseStart: v,
            verseEnd: v,
            version: id,
          ),
          text,
        ));
        if (results.length >= limit) break;
      }
    }
    return results;
  }
}

/// Loads the user's preferred XML file first so the app opens immediately,
/// then parses the remaining XML files in assets/bibles/ in the background.
class BibleRepository extends ChangeNotifier {
  static const _assetPrefix = 'assets/bibles/';
  static const _prefKey = 'default_version';

  final Map<String, BibleVersion> _versions = {};
  final List<String> warnings = [];
  bool loading = true;
  bool loadingRemaining = false;
  String? _selected;

  List<String> get versionIds => _versions.keys.toList()..sort();
  String? get selectedId => _selected;
  bool get isEmpty => _versions.isEmpty;

  /// The version with [id], falling back to the default one.
  BibleVersion? version(String? id) =>
      _versions[id] ?? (_selected == null ? null : _versions[_selected]);

  Future<void> select(String id) async {
    if (!_versions.containsKey(id)) return;
    _selected = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, id);
  }

  String _idFromPath(String path) => path
      .split('/')
      .last
      .replaceAll(RegExp(r'\.xml$', caseSensitive: false), '');

  Future<void> _loadSingle(String path) async {
    final id = _idFromPath(path);
    try {
      final text = await rootBundle.loadString(path, cache: false);
      final verses = await compute(parseBibleXml, text);
      if (verses.isEmpty) {
        warnings.add('$id: file loaded but no verses were recognised.');
      } else {
        _versions[id] = BibleVersion(id, verses);
      }
    } catch (e) {
      warnings.add('$id: could not be read ($e)');
    }
  }

  Future<void> load({String? preferredId}) async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final paths = manifest
          .listAssets()
          .where((p) =>
              p.startsWith(_assetPrefix) && p.toLowerCase().endsWith('.xml'))
          .toList()
        ..sort();

      if (paths.isEmpty) {
        warnings.add('No .xml files found in assets/bibles/.');
        loading = false;
        notifyListeners();
        return;
      }

      // Resolve preferred version from explicit parameter or saved SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final targetId = (preferredId != null && preferredId.isNotEmpty)
          ? preferredId
          : prefs.getString(_prefKey);

      String priorityPath = paths.first;
      if (targetId != null && targetId.isNotEmpty) {
        final targetLower = targetId.toLowerCase();
        priorityPath = paths.firstWhere(
          (p) => _idFromPath(p).toLowerCase() == targetLower,
          orElse: () => paths.firstWhere(
            (p) => _idFromPath(p).toLowerCase().contains(targetLower),
            orElse: () => paths.first,
          ),
        );
      }

      // 1. Load ONLY the priority translation first so SplashScreen dismisses fast
      await _loadSingle(priorityPath);
      final priorityId = _idFromPath(priorityPath);
      if (_versions.containsKey(priorityId)) {
        _selected = priorityId;
      } else if (_versions.isNotEmpty) {
        _selected = versionIds.first;
      }

      loading = false;
      final remainingPaths = paths.where((p) => p != priorityPath).toList();
      loadingRemaining = remainingPaths.isNotEmpty;
      notifyListeners();

      // 2. Load all remaining translations quietly in the background
      for (final path in remainingPaths) {
        await _loadSingle(path);
        if (_selected == null && _versions.isNotEmpty) {
          _selected = versionIds.first;
        }
        notifyListeners();
      }
    } catch (e) {
      warnings.add('Failed to load Bible files: $e');
      loading = false;
    } finally {
      loadingRemaining = false;
      notifyListeners();
    }
  }
}