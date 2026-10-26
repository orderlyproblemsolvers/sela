import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../bible/bible_repository.dart';
import '../motion.dart';
import '../notes/note.dart';
import '../notes/note_store.dart';
import '../notes/settings_store.dart';
import 'note_editor_screen.dart';
import 'settings_screen.dart';

enum _Section { notes, archive, trash }

enum _Act { pin, unpin, archive, unarchive, trash, restore, deleteForever }

String _when(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final year = d.year == now.year ? '' : ', ${d.year}';
  return '${m[d.month - 1]} ${d.day}$year';
}

class NotesListScreen extends StatefulWidget {
  const NotesListScreen({
    super.key,
    required this.notes,
    required this.bibles,
    required this.settings,
  });

  final NoteStore notes;
  final BibleRepository bibles;
  final SettingsStore settings;

  @override
  State<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  _Section _section = _Section.notes;
  String _query = '';
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  /// The note a "New note" tap will open (created before the transition).
  Note? _draft;

  @override
  void initState() {
    super.initState();
    unawaited(widget.notes.purgeTrash(widget.settings.trashDays));
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ navigation

  Widget _editorFor(Note note) => NoteEditorScreen(
        note: note,
        notes: widget.notes,
        bibles: widget.bibles,
        settings: widget.settings,
      );

  /// Used instead of the container transform when motion is reduced.
  void _openFade(Note note) {
    Navigator.of(context).push(fadeRoute<void>(_editorFor(note)));
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          settings: widget.settings,
          bibles: widget.bibles,
          notes: widget.notes,
        ),
      ),
    );
  }

  void _goTo(_Section s) {
    setState(() {
      _section = s;
      _selected.clear();
      _query = '';
      _search.clear();
    });
  }

  void _clearSelection() => setState(_selected.clear);

  void _clearSearch() {
    _search.clear();
    _searchFocus.unfocus();
    setState(() => _query = '');
  }

  void _handleBack() {
    if (_selecting) {
      _clearSelection();
    } else if (_query.isNotEmpty) {
      _clearSearch();
    } else if (_section != _Section.notes) {
      _goTo(_Section.notes);
    }
  }

  void _toggle(Note n) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.remove(n.id)) _selected.add(n.id);
    });
  }

  // --------------------------------------------------------------- filtering

  List<Note> _inSection(List<Note> all) {
    switch (_section) {
      case _Section.notes:
        return all.where((n) => !n.archived && !n.isTrashed).toList();
      case _Section.archive:
        return all.where((n) => n.archived && !n.isTrashed).toList();
      case _Section.trash:
        return all.where((n) => n.isTrashed).toList();
    }
  }

  bool _matches(Note n, String q) {
    final hay = '${n.title}\n${n.plain.isEmpty ? n.preview : n.plain}'
        .toLowerCase();
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }

  int _cmp(Note a, Note b) {
    if (_section == _Section.trash) {
      return (b.deletedAt ?? b.updatedAt).compareTo(a.deletedAt ?? a.updatedAt);
    }
    switch (widget.settings.sort) {
      case NoteSort.edited:
        return b.updatedAt.compareTo(a.updatedAt);
      case NoteSort.created:
        return b.createdAt.compareTo(a.createdAt);
      case NoteSort.title:
        return a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
    }
  }

  // ----------------------------------------------------------------- actions

  String _count(int n) => n == 1 ? 'Note' : '$n notes';

  void _snack(String msg, {VoidCallback? undo}) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 4),
        action: undo == null
            ? null
            : SnackBarAction(label: 'Undo', onPressed: undo),
      ),
    );
  }

  Future<bool> _confirm(String title, String body, String yes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _apply(_Act a, List<Note> targets) async {
    if (targets.isEmpty) return;
    final notes = widget.notes;
    final what = _count(targets.length);

    switch (a) {
      case _Act.pin:
        await notes.setPinned(targets, true);
      case _Act.unpin:
        await notes.setPinned(targets, false);
      case _Act.archive:
        await notes.setArchived(targets, true);
        _snack('$what archived', undo: () => notes.setArchived(targets, false));
      case _Act.unarchive:
        await notes.setArchived(targets, false);
        _snack('$what unarchived', undo: () => notes.setArchived(targets, true));
      case _Act.trash:
        await notes.trash(targets);
        _snack('$what moved to Trash', undo: () => notes.restore(targets));
      case _Act.restore:
        await notes.restore(targets);
        _snack('$what restored');
      case _Act.deleteForever:
        final ok = await _confirm(
          'Delete forever?',
          targets.length == 1
              ? 'This note will be permanently deleted.'
              : '${targets.length} notes will be permanently deleted.',
          'Delete forever',
        );
        if (!ok) return;
        await notes.deleteForever(targets);
    }
    if (mounted) _clearSelection();
  }

  List<Note> _selectedNotes() =>
      widget.notes.notes.where((n) => _selected.contains(n.id)).toList();

  Future<void> _trashedDialog(Note n) async {
    final act = await showDialog<_Act>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('This note is in Trash'),
        content: const Text('Restore it to view or edit it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _Act.deleteForever),
            child: const Text('Delete forever'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _Act.restore),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (act != null) await _apply(act, [n]);
  }

  Future<void> _emptyTrash() async {
    final ok = await _confirm(
      'Empty Trash?',
      'All notes in Trash will be permanently deleted.',
      'Empty Trash',
    );
    if (ok) await widget.notes.emptyTrash();
  }

  // --------------------------------------------------------------------- UI

  Widget _drawer(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return NavigationDrawer(
      selectedIndex: _section.index,
      onDestinationSelected: (i) {
        _scaffoldKey.currentState?.closeDrawer();
        if (i < 3) {
          _goTo(_Section.values[i]);
        } else {
          _openSettings();
        }
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 16, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _BrandLogo(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sela', style: tt.headlineSmall),
                    const SizedBox(height: 2),
                    Text(
                      'Study, offline',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.lightbulb_outline),
          selectedIcon: Icon(Icons.lightbulb),
          label: Text('Notes'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.archive_outlined),
          selectedIcon: Icon(Icons.archive),
          label: Text('Archive'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.delete_outline),
          selectedIcon: Icon(Icons.delete),
          label: Text('Trash'),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 8, 28, 8),
          child: Divider(),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Settings'),
        ),
      ],
    );
  }

  Widget _fab(ColorScheme cs, bool show, bool reduce) {
    return AnimatedSwitcher(
      duration: Duration(milliseconds: reduce ? 120 : 420),
      switchInCurve: const SpringCurve(),
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, a) => reduce
          ? FadeTransition(opacity: a, child: child)
          : ScaleTransition(
              scale: a,
              child: FadeTransition(opacity: a, child: child),
            ),
      child: !show
          ? const SizedBox.shrink(key: ValueKey('no-fab'))
          : PressScale(
              key: const ValueKey('fab'),
              pressedScale: 0.94,
              child: OpenContainer<void>(
                closedColor: cs.primary,
                openColor: cs.surface,
                middleColor: cs.surface,
                closedElevation: 3,
                openElevation: 0,
                closedShape: const StadiumBorder(),
                openShape: const RoundedRectangleBorder(),
                transitionDuration: const Duration(milliseconds: 420),
                tappable: false,
                closedBuilder: (context, open) => InkWell(
                  onTap: () {
                    _draft = widget.notes.newNote();
                    if (reduce) {
                      _openFade(_draft!);
                    } else {
                      open();
                    }
                  },
                  child: SizedBox(
                    height: 56,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, color: cs.onPrimary),
                          const SizedBox(width: 10),
                          Text(
                            'New note',
                            style: TextStyle(
                              color: cs.onPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                openBuilder: (context, _) =>
                    _editorFor(_draft ?? widget.notes.newNote()),
              ),
            ),
    );
  }

  Widget _searchBar(ColorScheme cs, String hint) {
    return Material(
      key: const ValueKey('search'),
      color: cs.surfaceContainerLowest,
      shape: StadiumBorder(side: BorderSide(color: cs.outlineVariant)),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Menu',
              icon: const Icon(Icons.menu),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            Expanded(
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: hint,
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            if (_query.isNotEmpty)
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close),
                onPressed: _clearSearch,
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Icon(Icons.search, color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _selectionBar(
    ColorScheme cs,
    TextTheme tt,
    List<Note> sel,
    List<Note> shown,
  ) {
    final fg = cs.onPrimaryContainer;
    final allPinned = sel.isNotEmpty && sel.every((n) => n.pinned);

    Widget btn(IconData icon, String tip, _Act act) => IconButton(
          tooltip: tip,
          color: fg,
          icon: Icon(icon),
          onPressed: () => _apply(act, sel),
        );

    final actions = <Widget>[
      if (_section == _Section.notes) ...[
        btn(allPinned ? Icons.push_pin : Icons.push_pin_outlined,
            allPinned ? 'Unpin' : 'Pin', allPinned ? _Act.unpin : _Act.pin),
        btn(Icons.archive_outlined, 'Archive', _Act.archive),
        btn(Icons.delete_outline, 'Delete', _Act.trash),
      ],
      if (_section == _Section.archive) ...[
        btn(Icons.unarchive_outlined, 'Unarchive', _Act.unarchive),
        btn(Icons.delete_outline, 'Delete', _Act.trash),
      ],
      if (_section == _Section.trash) ...[
        btn(Icons.restore_from_trash_outlined, 'Restore', _Act.restore),
        btn(Icons.delete_forever_outlined, 'Delete forever', _Act.deleteForever),
      ],
    ];

    return Material(
      key: const ValueKey('selection'),
      color: cs.primaryContainer,
      shape: const StadiumBorder(),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Cancel selection',
              color: fg,
              icon: const Icon(Icons.close),
              onPressed: _clearSelection,
            ),
            Expanded(
              child: Text(
                '${sel.length} selected',
                style: tt.titleLarge?.copyWith(fontSize: 18, color: fg),
              ),
            ),
            ...actions,
            PopupMenuButton<String>(
              tooltip: 'More',
              iconColor: fg,
              onSelected: (_) => setState(() {
                _selected
                  ..clear()
                  ..addAll(shown.map((n) => n.id));
              }),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'all', child: Text('Select all')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<Note> list, int cols) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: cols,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childCount: list.length,
        itemBuilder: (context, i) {
          final n = list[i];
          return _NoteCard(
            key: ValueKey(n.id),
            note: n,
            section: _section,
            selecting: _selecting,
            selected: _selected.contains(n.id),
            footer: _footer(n),
            editorBuilder: () => _editorFor(n),
            onOpenReduced: () => _openFade(n),
            onToggle: () => _toggle(n),
            onTrashedTap: () => unawaited(_trashedDialog(n)),
            onAction: (a) => _apply(a, [n]),
          );
        },
      ),
    );
  }

  String _footer(Note n) {
    if (_section == _Section.trash) {
      final days = widget.settings.trashDays;
      if (days > 0 && n.deletedAt != null) {
        final left = days - DateTime.now().difference(n.deletedAt!).inDays;
        return left <= 0 ? 'Deleting soon' : '$left days left';
      }
      return 'Deleted ${_when(n.deletedAt ?? n.updatedAt)}';
    }
    return _when(n.updatedAt);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final hint = switch (_section) {
      _Section.notes => 'Search your notes',
      _Section.archive => 'Search archive',
      _Section.trash => 'Search trash',
    };

    return PopScope(
      canPop: !_selecting && _query.isEmpty && _section == _Section.notes,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _drawer(context),
        floatingActionButton: _fab(
          cs,
          _section == _Section.notes && !_selecting,
          Motion.reduced(context),
        ),
        body: SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: Listenable.merge(
                [widget.notes, widget.bibles, widget.settings]),
            builder: (context, _) {
              final all = widget.notes.notes;
              final inSection = _inSection(all);
              final q = _query.trim().toLowerCase();
              final shown = q.isEmpty
                  ? inSection
                  : inSection.where((n) => _matches(n, q)).toList();

              final pinned = _section == _Section.notes
                  ? (shown.where((n) => n.pinned).toList()..sort(_cmp))
                  : <Note>[];
              final others = (_section == _Section.notes
                      ? shown.where((n) => !n.pinned)
                      : shown)
                  .toList()
                ..sort(_cmp);

              final sel = all.where((n) => _selected.contains(n.id)).toList();
              final reduce = Motion.reduced(context);

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: AnimatedSwitcher(
                      duration: Duration(milliseconds: reduce ? 120 : 380),
                      switchInCurve: const SpringCurve(),
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: reduce
                            ? child
                            : ScaleTransition(
                                scale: Tween<double>(begin: 0.96, end: 1.0)
                                    .animate(a),
                                child: child,
                              ),
                      ),
                      child: _selecting
                          ? _selectionBar(cs, tt, sel, shown)
                          : _searchBar(cs, hint),
                    ),
                  ),
                  Expanded(
                    child: PageTransitionSwitcher(
                      duration: Duration(milliseconds: reduce ? 160 : 340),
                      transitionBuilder: (child, anim, secondary) => reduce
                          ? FadeTransition(
                              opacity: anim,
                              child: FadeTransition(
                                opacity: ReverseAnimation(secondary),
                                child: child,
                              ),
                            )
                          : FadeThroughTransition(
                              animation: anim,
                              secondaryAnimation: secondary,
                              fillColor: Colors.transparent,
                              child: child,
                            ),
                      child: KeyedSubtree(
                        key: ValueKey(_section),
                        child: LayoutBuilder(
                          builder: (context, c) {
                            final cols = c.maxWidth < 520
                                ? 2
                                : (c.maxWidth < 820 ? 3 : 4);
                            return CustomScrollView(
                              slivers: [
                                if (_section == _Section.archive)
                                  const SliverToBoxAdapter(
                                    child: _Intro(
                                      title: 'Archive',
                                      body:
                                          'Archived notes are kept here, out of your main list.',
                                    ),
                                  ),
                                if (_section == _Section.trash)
                                  SliverToBoxAdapter(
                                    child: _Intro(
                                      title: 'Trash',
                                      body: widget.settings.trashDays == 0
                                          ? 'Notes stay here until you delete them.'
                                          : 'Notes are deleted forever after ${widget.settings.trashDays} days.',
                                      action: inSection.isEmpty
                                          ? null
                                          : TextButton(
                                              onPressed: _emptyTrash,
                                              child: const Text('Empty Trash'),
                                            ),
                                    ),
                                  ),
                                if (widget.bibles.loading)
                                  const SliverToBoxAdapter(
                                    child: LinearProgressIndicator(minHeight: 2),
                                  ),
                                if (_section == _Section.notes &&
                                    !widget.bibles.loading &&
                                    (widget.bibles.isEmpty ||
                                        widget.bibles.warnings.isNotEmpty))
                                  SliverToBoxAdapter(
                                    child: Container(
                                      margin: const EdgeInsets.fromLTRB(
                                          16, 8, 16, 8),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: cs.errorContainer,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            widget.bibles.isEmpty
                                                ? 'No Bible loaded. Put your XML files in assets/bibles/ and rebuild.'
                                                : 'Some Bible files had problems:',
                                            style: TextStyle(
                                                color: cs.onErrorContainer),
                                          ),
                                          for (final w
                                              in widget.bibles.warnings)
                                            Text('• $w',
                                                style: TextStyle(
                                                    color:
                                                        cs.onErrorContainer)),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (shown.isEmpty)
                                  SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: _Empty(
                                      icon: q.isNotEmpty
                                          ? Icons.search_off
                                          : switch (_section) {
                                              _Section.notes =>
                                                Icons.menu_book_outlined,
                                              _Section.archive =>
                                                Icons.archive_outlined,
                                              _Section.trash =>
                                                Icons.delete_outline,
                                            },
                                      title: q.isNotEmpty
                                          ? 'No results for “${_query.trim()}”'
                                          : switch (_section) {
                                              _Section.notes => 'No notes yet',
                                              _Section.archive =>
                                                'Nothing archived',
                                              _Section.trash => 'Trash is empty',
                                            },
                                      body: q.isNotEmpty
                                          ? 'Try a different word.'
                                          : switch (_section) {
                                              _Section.notes =>
                                                'Tap “New note”, then type a reference like James 1:2 and the verse appears.',
                                              _Section.archive =>
                                                'Archive notes you want to keep but not see every day.',
                                              _Section.trash =>
                                                'Deleted notes show up here.',
                                            },
                                    ),
                                  ),
                                if (pinned.isNotEmpty) ...[
                                  SliverToBoxAdapter(
                                    child: _SectionHeader(
                                      icon: Icons.push_pin,
                                      label: 'Pinned',
                                      count: pinned.length,
                                      accent: true,
                                    ),
                                  ),
                                  _grid(pinned, cols),
                                  const SliverToBoxAdapter(
                                      child: SizedBox(height: 18)),
                                ],
                                if (others.isNotEmpty) ...[
                                  if (pinned.isNotEmpty)
                                    SliverToBoxAdapter(
                                      child: _SectionHeader(
                                        icon: Icons.notes,
                                        label: 'Others',
                                        count: others.length,
                                      ),
                                    ),
                                  _grid(others, cols),
                                ],
                                const SliverToBoxAdapter(
                                    child: SizedBox(height: 110)),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- small pieces

/// Renders the Sela brand logo from assets. If the asset is not present yet,
/// it falls back to a simple icon so the drawer never crashes.
class _BrandLogo extends StatelessWidget {
  const _BrandLogo({this.size = 40});

  final double size;

  static const _assetPath = 'assets/images/sela_logo.png';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.asset(
        _assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          width: size,
          height: size,
          color: cs.primaryContainer,
          alignment: Alignment.center,
          child: Icon(
            Icons.menu_book,
            size: size * 0.6,
            color: cs.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.count,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = accent ? cs.primary : cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Text(
            '${label.toUpperCase()}  ·  $count',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(
              color: accent ? cs.primary.withValues(alpha: 0.35) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.title, required this.body, this.action});

  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tt.headlineSmall),
                const SizedBox(height: 4),
                Text(body,
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final reduce = Motion.reduced(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: reduce ? 150 : 500),
      curve: const SpringCurve(duration: Duration(milliseconds: 500)),
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, reduce ? 0 : 14 * (1 - v)),
          child: child,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: cs.outline),
              const SizedBox(height: 14),
              Text(title, style: tt.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    super.key,
    required this.note,
    required this.section,
    required this.selecting,
    required this.selected,
    required this.footer,
    required this.editorBuilder,
    required this.onOpenReduced,
    required this.onToggle,
    required this.onTrashedTap,
    required this.onAction,
  });

  final Note note;
  final _Section section;
  final bool selecting;
  final bool selected;
  final String footer;
  final Widget Function() editorBuilder;
  final VoidCallback onOpenReduced;
  final VoidCallback onToggle;
  final VoidCallback onTrashedTap;
  final ValueChanged<_Act> onAction;

  PopupMenuItem<_Act> _item(
    _Act a,
    IconData icon,
    String label, {
    Color? color,
  }) =>
      PopupMenuItem(
        value: a,
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      );

  List<PopupMenuEntry<_Act>> _menu(ColorScheme cs) {
    switch (section) {
      case _Section.notes:
        return [
          note.pinned
              ? _item(_Act.unpin, Icons.push_pin_outlined, 'Unpin')
              : _item(_Act.pin, Icons.push_pin, 'Pin'),
          _item(_Act.archive, Icons.archive_outlined, 'Archive'),
          _item(_Act.trash, Icons.delete_outline, 'Delete', color: cs.error),
        ];
      case _Section.archive:
        return [
          _item(_Act.unarchive, Icons.unarchive_outlined, 'Unarchive'),
          _item(_Act.trash, Icons.delete_outline, 'Delete', color: cs.error),
        ];
      case _Section.trash:
        return [
          _item(_Act.restore, Icons.restore_from_trash_outlined, 'Restore'),
          _item(_Act.deleteForever, Icons.delete_forever_outlined,
              'Delete forever',
              color: cs.error),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final reduce = Motion.reduced(context);
    final hasTitle = note.title.trim().isNotEmpty;

    final Color fill = selected
        ? Color.alphaBlend(
            cs.primaryContainer.withValues(alpha: 0.6),
            cs.surfaceContainerLowest)
        : note.pinned
            ? Color.alphaBlend(
                cs.primaryContainer.withValues(alpha: 0.3),
                cs.surfaceContainerLowest)
            : cs.surfaceContainerLowest;

    final Color border = selected
        ? cs.primary
        : note.pinned
            ? cs.primary.withValues(alpha: 0.4)
            : cs.outlineVariant;

    // Keep the border geometry identical between closed and open shapes so
    // the content box never shrinks mid-transform (the source of the
    // ~7.7px overflow on short cards). Only the radius animates 18 -> 0.
    final side = BorderSide(color: border, width: selected ? 2 : 1);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: side,
    );
    final openShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
      side: side,
    );

    // Selected cards settle slightly smaller, like Photos.
    return PressScale(
      restScale: selected ? 0.965 : 1.0,
      child: OpenContainer<void>(
        closedColor: fill,
        openColor: cs.surface,
        middleColor: cs.surface,
        closedElevation: 0,
        openElevation: 0,
        closedShape: shape,
        openShape: openShape,
        transitionDuration: const Duration(milliseconds: 420),
        tappable: false,
        closedBuilder: (context, open) => InkWell(
          onTap: () {
            if (selecting) {
              onToggle();
            } else if (note.isTrashed) {
              onTrashedTap();
            } else if (reduce) {
              onOpenReduced();
            } else {
              open();
            }
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            onToggle();
          },
          // Clip to the card radius so any sub-pixel overflow during the
          // transform is clipped instead of asserting.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6, right: 4),
                          child: Text(
                            hasTitle ? note.title : 'Untitled',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: tt.titleLarge?.copyWith(
                              fontSize: 19,
                              height: 1.25,
                              fontWeight: FontWeight.w500,
                              color: hasTitle ? cs.onSurface : cs.outline,
                              fontStyle: hasTitle
                                  ? FontStyle.normal
                                  : FontStyle.italic,
                            ),
                          ),
                        ),
                      ),
                      if (selecting)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 4, 8, 0),
                          child: AnimatedSwitcher(
                            duration: Duration(milliseconds: reduce ? 100 : 320),
                            switchInCurve: const SpringCurve(
                              damping: 0.8,
                              duration: Duration(milliseconds: 320),
                            ),
                            transitionBuilder: (c, a) => reduce
                                ? FadeTransition(opacity: a, child: c)
                                : ScaleTransition(scale: a, child: c),
                            child: Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              key: ValueKey(selected),
                              size: 22,
                              color: selected ? cs.primary : cs.outline,
                            ),
                          ),
                        )
                      else ...[
                        if (note.pinned)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Icon(Icons.push_pin,
                                size: 16, color: cs.primary),
                          ),
                        SizedBox(
                          width: 34,
                          height: 34,
                          child: PopupMenuButton<_Act>(
                            padding: EdgeInsets.zero,
                            tooltip: 'Note options',
                            icon: Icon(Icons.more_horiz,
                                size: 20, color: cs.onSurfaceVariant),
                            onSelected: onAction,
                            itemBuilder: (_) => _menu(cs),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (note.preview.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    // Flexible lets the preview shrink if the card's max
                    // height is briefly tight during the transform.
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          note.preview,
                          maxLines: 9,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    footer,
                    style: tt.labelSmall?.copyWith(color: cs.outline),
                  ),
                ],
              ),
            ),
          ),
        ),
        openBuilder: (context, _) => editorBuilder(),
      ),
    );
  }
}