import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bible_parser.dart';

class BibleVersion {
  BibleVersion(this.id, this.verses);

  final String id;
  final Map<int, String> verses;

  String? verse(int book, int chapter, int verse) =>
      verses[verseKey(book, chapter, verse)];
}

/// Loads every XML file in assets/bibles/ once, fully offline.
class BibleRepository extends ChangeNotifier {
  static const _assetPrefix = 'assets/bibles/';
  static const _prefKey = 'default_version';

  final Map<String, BibleVersion> _versions = {};
  final List<String> warnings = [];
  bool loading = true;
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

  Future<void> load() async {
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
      }

      for (final path in paths) {
        final id = path
            .split('/')
            .last
            .replaceAll(RegExp(r'\.xml$', caseSensitive: false), '');
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

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null && _versions.containsKey(saved)) {
        _selected = saved;
      } else if (_versions.isNotEmpty) {
        _selected = versionIds.first;
      }
    } catch (e) {
      warnings.add('Failed to load Bible files: $e');
    }
    loading = false;
    notifyListeners();
  }
}
