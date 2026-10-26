import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NoteSort { edited, created, title }

/// App preferences, saved on the device. (The default Bible translation is
/// stored by BibleRepository.)
class SettingsStore extends ChangeNotifier {
  late final SharedPreferences _p;

  ThemeMode _themeMode = ThemeMode.system;
  double _editorScale = 1.0;
  bool _autoInsertVerses = true;
  bool _insertExpanded = true;
  NoteSort _sort = NoteSort.edited;
  int _trashDays = 30; // 0 = keep until emptied
  bool _reduceMotion = false;

  ThemeMode get themeMode => _themeMode;
  double get editorScale => _editorScale;
  bool get autoInsertVerses => _autoInsertVerses;
  bool get insertExpanded => _insertExpanded;
  NoteSort get sort => _sort;
  int get trashDays => _trashDays;
  bool get reduceMotion => _reduceMotion;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    _themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == _p.getString('theme'),
      orElse: () => ThemeMode.system,
    );
    _editorScale =
        (_p.getDouble('editor_scale') ?? 1.0).clamp(0.85, 1.5).toDouble();
    _autoInsertVerses = _p.getBool('auto_insert') ?? true;
    _insertExpanded = _p.getBool('insert_expanded') ?? true;
    _sort = NoteSort.values.firstWhere(
      (s) => s.name == _p.getString('sort'),
      orElse: () => NoteSort.edited,
    );
    _trashDays = _p.getInt('trash_days') ?? 30;
    _reduceMotion = _p.getBool('reduce_motion') ?? false;
  }

  Future<void> setThemeMode(ThemeMode v) async {
    _themeMode = v;
    notifyListeners();
    await _p.setString('theme', v.name);
  }

  Future<void> setEditorScale(double v) async {
    _editorScale = v;
    notifyListeners();
    await _p.setDouble('editor_scale', v);
  }

  Future<void> setAutoInsertVerses(bool v) async {
    _autoInsertVerses = v;
    notifyListeners();
    await _p.setBool('auto_insert', v);
  }

  Future<void> setInsertExpanded(bool v) async {
    _insertExpanded = v;
    notifyListeners();
    await _p.setBool('insert_expanded', v);
  }

  Future<void> setSort(NoteSort v) async {
    _sort = v;
    notifyListeners();
    await _p.setString('sort', v.name);
  }

  Future<void> setTrashDays(int v) async {
    _trashDays = v;
    notifyListeners();
    await _p.setInt('trash_days', v);
  }

  Future<void> setReduceMotion(bool v) async {
    _reduceMotion = v;
    notifyListeners();
    await _p.setBool('reduce_motion', v);
  }
}
