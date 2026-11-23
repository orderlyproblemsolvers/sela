import 'dart:async';

import 'package:flutter/material.dart';

import '../bible/bible_repository.dart';
import '../motion.dart';
import '../notes/note_store.dart';
import '../notes/settings_store.dart';
import 'notes_list_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.notes,
    required this.bibles,
    required this.settings,
  });

  final NoteStore notes;
  final BibleRepository bibles;
  final SettingsStore settings;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );

    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctl,
        curve: const Interval(0.0, 0.72, curve: SpringCurve(damping: 0.88)),
      ),
    );

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctl,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      ),
    );

    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctl,
        curve: const Interval(0.28, 0.85, curve: Curves.easeOut),
      ),
    );

    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _ctl,
        curve: const Interval(0.28, 0.95, curve: SpringCurve()),
      ),
    );

    unawaited(_boot());
  }

  Future<void> _boot() async {
    _ctl.forward();

    // Wait for the spring animation and the preferred Bible translation
    final minDelay = Future<void>.delayed(const Duration(milliseconds: 1150));
    await Future.wait([
      minDelay,
      _waitForPreferredBible(),
    ]);

    if (!mounted || _navigated) return;
    _navigated = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, _, _) => NotesListScreen(
          notes: widget.notes,
          bibles: widget.bibles,
          settings: widget.settings,
        ),
        transitionsBuilder: (context, animation, _, child) {
          final curve = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(opacity: curve, child: child);
        },
      ),
    );
  }

  Future<void> _waitForPreferredBible() async {
    if (!widget.bibles.loading) return;
    final completer = Completer<void>();
    void listener() {
      if (!widget.bibles.loading && !completer.isCompleted) {
        widget.bibles.removeListener(listener);
        completer.complete();
      }
    }

    widget.bibles.addListener(listener);
    await completer.future;
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final reduce = Motion.reduced(context);

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 3),
                FadeTransition(
                  opacity: reduce ? const AlwaysStoppedAnimation(1.0) : _logoFade,
                  child: ScaleTransition(
                    scale:
                        reduce ? const AlwaysStoppedAnimation(1.0) : _logoScale,
                    child: SizedBox(
                      width: 96,
                      height: 96,
                      child: Image.asset(
                        'assets/images/sela_logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.menu_book_rounded,
                          size: 56,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FadeTransition(
                  opacity: reduce ? const AlwaysStoppedAnimation(1.0) : _textFade,
                  child: SlideTransition(
                    position: reduce
                        ? const AlwaysStoppedAnimation(Offset.zero)
                        : _textSlide,
                    child: Text(
                      'Sela',
                      style: tt.displaySmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
                const Spacer(flex: 3),
                FadeTransition(
                  opacity: reduce ? const AlwaysStoppedAnimation(1.0) : _textFade,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: Text(
                      '“Be still, and know…”',
                      style: tt.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: cs.outline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}