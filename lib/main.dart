import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'bible/bible_repository.dart';
import 'motion.dart';
import 'notes/note_store.dart';
import 'notes/settings_store.dart';
import 'screens/notes_list_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsStore();
  final notes = NoteStore();
  final bibles = BibleRepository();
  await settings.init();
  await notes.init();
  runApp(BibleNotesApp(notes: notes, bibles: bibles, settings: settings));
  // Parse the Bible files in the background; the UI updates when ready.
  unawaited(bibles.load());
}

class BibleNotesApp extends StatelessWidget {
  const BibleNotesApp({
    super.key,
    required this.notes,
    required this.bibles,
    required this.settings,
  });

  final NoteStore notes;
  final BibleRepository bibles;
  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'Sela',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: settings.themeMode,
        builder: (context, child) => Motion(
          reduce:
              settings.reduceMotion || MediaQuery.disableAnimationsOf(context),
          child: Material(
            type: MaterialType.transparency,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: NotesListScreen(notes: notes, bibles: bibles, settings: settings),
      ),
    );
  }
}
