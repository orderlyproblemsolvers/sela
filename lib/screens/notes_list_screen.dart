import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_icons.dart';
import '../bible/bible_repository.dart';
import '../motion.dart';
import '../notes/note.dart';
import '../notes/note_store.dart';
import '../notes/settings_store.dart';
import '../tokens.dart';
import 'note_editor_screen.dart';
import 'settings_screen.dart';

enum _Section { notes, archive, trash }

enum _Act {
  select,
  selectAll,
  pin,
  unpin,
  movePinUp,
  movePinDown,
  moveToFolder,
  removeFromFolder,
  archive,
  unarchive,
  trash,
  restore,
  deleteForever,
}

enum _FolderDelete { keepNotes, trashAll }

/// Space kept below the lists so the last card clears the FAB.
const double _fabClearance = 96;

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
  String? _activeFolderId;
  String _query = '';
  String? _selectedTag;
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

  void _resetView() {
    _selected.clear();
    _selectedTag = null;
    _query = '';
    _search.clear();
  }

  void _goTo(_Section s) {
    setState(() {
      _section = s;
      _activeFolderId = null;
      _resetView();
    });
  }

  void _openFolder(String folderId) {
    setState(() {
      _activeFolderId = folderId;
      _resetView();
    });
  }

  void _exitFolder() {
    setState(() {
      _activeFolderId = null;
      _selected.clear();
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
    } else if (_selectedTag != null) {
      setState(() => _selectedTag = null);
    } else if (_activeFolderId != null) {
      _exitFolder();
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
        return a.displayTitle
            .toLowerCase()
            .compareTo(b.displayTitle.toLowerCase());
    }
  }

  int _cmpPinned(Note a, Note b) {
    final orderCmp = a.pinOrder.compareTo(b.pinOrder);
    return orderCmp != 0 ? orderCmp : _cmp(a, b);
  }

  // ---------------------------------------------------------------- folders

  Future<void> _promptCreateFolder() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _FolderNameDialog(
        title: 'New folder',
        confirmLabel: 'Create',
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await widget.notes.createFolder(name);
    }
  }

  Future<void> _promptRenameFolder(NoteFolder folder) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _FolderNameDialog(
        title: 'Rename folder',
        confirmLabel: 'Save',
        initialValue: folder.name,
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await widget.notes.renameFolder(folder.id, name);
    }
  }

  Future<void> _confirmDeleteFolder(NoteFolder folder) async {
    final count = widget.notes.noteCountInFolder(folder.id);

    if (count == 0) {
      final ok = await _confirm(
        'Move “${folder.name}” to Trash?',
        'You can restore it later from Trash.',
        'Move to Trash',
      );
      if (!ok) return;
      if (_activeFolderId == folder.id) _exitFolder();
      await widget.notes.trashFolder(folder.id, trashNotes: false);
      _snack(
        'Folder moved to Trash',
        undo: () => widget.notes.restoreFolder(folder.id),
      );
      return;
    }

    final choice = await showDialog<_FolderDelete>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete “${folder.name}”?'),
        content: Text(
          'This folder has ${count == 1 ? '1 note' : '$count notes'}. '
          'Move the notes to Trash too, or keep them in your main list?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _FolderDelete.keepNotes),
            child: const Text('Keep notes'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _FolderDelete.trashAll),
            child: const Text('Trash all'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;
    if (_activeFolderId == folder.id) _exitFolder();

    final trashNotes = choice == _FolderDelete.trashAll;
    await widget.notes.trashFolder(folder.id, trashNotes: trashNotes);
    _snack(
      trashNotes
          ? 'Folder and notes moved to Trash'
          : 'Folder moved to Trash (notes kept)',
      undo: () => widget.notes.restoreFolder(folder.id),
    );
  }

  Future<void> _moveNotesToFolder(
    List<Note> targets,
    String? folderId, {
    String? folderName,
  }) async {
    if (targets.isEmpty) return;
    final previous = {for (final n in targets) n.id: n.folderId};
    await widget.notes.moveToFolder(targets, folderId);

    final what = _count(targets.length);
    final dest = folderId == null ? 'main notes' : '“${folderName ?? 'folder'}”';
    _snack(
      '$what moved to $dest',
      undo: () async {
        for (final n in targets) {
          await widget.notes.moveToFolder([n], previous[n.id]);
        }
      },
    );
  }

  Future<void> _pickFolderFor(List<Note> targets) async {
    final folders = widget.notes.folders;
    final picked = await showModalBottomSheet<String?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.xl, 0, Space.xl, Space.sm),
              child: Text(
                'Move to folder',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(AppIcons.folderOutput),
              title: const Text('Main notes (no folder)'),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            for (final f in folders)
              ListTile(
                leading: const Icon(AppIcons.folder),
                title: Text(f.name),
                onTap: () => Navigator.pop(ctx, f.id),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(AppIcons.folderPlus),
              title: const Text('New folder…'),
              onTap: () => Navigator.pop(ctx, '__new__'),
            ),
            const SizedBox(height: Space.sm),
          ],
        ),
      ),
    );

    if (picked == null || !mounted) return;
    if (picked == '__new__') {
      await _promptCreateFolder();
      return;
    }
    if (picked.isEmpty) {
      await _moveNotesToFolder(targets, null);
    } else {
      final f = widget.notes.folderById(picked);
      await _moveNotesToFolder(targets, picked, folderName: f?.name);
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
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yes),
          ),
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
      case _Act.select:
        _toggle(targets.first);
        return;
      case _Act.selectAll:
        return; // handled by the selection bar, which knows what is shown
      case _Act.pin:
        await notes.setPinned(targets, true);
      case _Act.unpin:
        await notes.setPinned(targets, false);
      case _Act.movePinUp:
      case _Act.movePinDown:
        final currentPinned = _inSection(notes.notes)
            .where((n) => n.pinned)
            .toList()
          ..sort(_cmpPinned);
        await notes.movePinned(
          targets.first,
          a == _Act.movePinUp ? -1 : 1,
          currentPinned,
        );
      case _Act.moveToFolder:
        await _pickFolderFor(targets);
      case _Act.removeFromFolder:
        await _moveNotesToFolder(targets, null);
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
      'All folders and notes in Trash will be permanently deleted.',
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
          padding: const EdgeInsets.fromLTRB(28, Space.xxl, Space.lg, Space.lg),
          child: Row(
            children: [
              const _BrandLogo(size: 40),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sela', style: tt.headlineSmall),
                    Text(
                      'Study, offline',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const NavigationDrawerDestination(
          icon: Icon(AppIcons.notes),
          selectedIcon: Icon(AppIcons.notesSelected),
          label: Text('Notes'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(AppIcons.archive),
          selectedIcon: Icon(AppIcons.archiveSelected),
          label: Text('Archive'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(AppIcons.trash),
          selectedIcon: Icon(AppIcons.trashSelected),
          label: Text('Trash'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28, vertical: Space.sm),
          child: Divider(),
        ),
        const NavigationDrawerDestination(
          icon: Icon(AppIcons.settings),
          selectedIcon: Icon(AppIcons.settingsSelected),
          label: Text('Settings'),
        ),
      ],
    );
  }

  Widget _fab(ColorScheme cs, bool show, bool reduce) {
    // It only appears or disappears (no gesture momentum), so no overshoot.
    return AnimatedSwitcher(
      duration: reduce ? Dur.fast : Dur.base,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, a) => reduce
          ? FadeTransition(opacity: a, child: child)
          : ScaleTransition(
              scale: Tween<double>(begin: 0.85, end: 1).animate(a),
              child: FadeTransition(opacity: a, child: child),
            ),
      child: !show
          ? const SizedBox.shrink(key: ValueKey('no-fab'))
          : PressScale(
              key: const ValueKey('fab'),
              pressedScale: 0.96,
              child: OpenContainer<void>(
                closedColor: cs.primary,
                openColor: cs.surface,
                middleColor: cs.surface,
                closedElevation: 3,
                openElevation: 0,
                closedShape: const StadiumBorder(),
                openShape: const RoundedRectangleBorder(),
                transitionDuration: Dur.route,
                tappable: false,
                closedBuilder: (context, open) => InkWell(
                  onTap: () {
                    _draft = widget.notes.newNote(folderId: _activeFolderId);
                    if (reduce) {
                      _openFade(_draft!);
                    } else {
                      open();
                    }
                  },
                  child: SizedBox(
                    height: 56,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(AppIcons.add, color: cs.onPrimary),
                          const SizedBox(width: Space.sm),
                          Text(
                            'New note',
                            style: TextStyle(
                              color: cs.onPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                openBuilder: (context, _) => _editorFor(
                    _draft ?? widget.notes.newNote(folderId: _activeFolderId)),
              ),
            ),
    );
  }

  Widget _searchBar(ColorScheme cs, String hint, bool canAddFolder) {
    return Material(
      key: const ValueKey('search'),
      color: cs.surfaceContainerLowest,
      shape: StadiumBorder(side: BorderSide(color: cs.outlineVariant)),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Menu',
              icon: const Icon(AppIcons.menu),
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
                icon: const Icon(AppIcons.close),
                onPressed: _clearSearch,
              )
            else if (canAddFolder)
              IconButton(
                tooltip: 'New folder',
                icon: Icon(AppIcons.folderPlus, color: cs.onSurfaceVariant),
                onPressed: _promptCreateFolder,
              )
            else
              const SizedBox(width: Space.lg),
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

    PopupMenuItem<_Act> item(_Act a, String label) =>
        PopupMenuItem(value: a, child: Text(label));

    // Two primary buttons at most, so the count never gets squeezed out on a
    // narrow phone. Everything else lives in the overflow menu.
    final List<Widget> actions;
    final List<PopupMenuEntry<_Act>> overflow;
    switch (_section) {
      case _Section.notes:
        actions = [
          btn(AppIcons.folder, 'Move to folder', _Act.moveToFolder),
          btn(AppIcons.trash, 'Delete', _Act.trash),
        ];
        overflow = [
          item(allPinned ? _Act.unpin : _Act.pin, allPinned ? 'Unpin' : 'Pin'),
          item(_Act.archive, 'Archive'),
          item(_Act.selectAll, 'Select all'),
        ];
      case _Section.archive:
        actions = [
          btn(AppIcons.unarchive, 'Unarchive', _Act.unarchive),
          btn(AppIcons.trash, 'Delete', _Act.trash),
        ];
        overflow = [item(_Act.selectAll, 'Select all')];
      case _Section.trash:
        actions = [
          btn(AppIcons.restore, 'Restore', _Act.restore),
          btn(AppIcons.deleteForever, 'Delete forever', _Act.deleteForever),
        ];
        overflow = [item(_Act.selectAll, 'Select all')];
    }

    return Material(
      key: const ValueKey('selection'),
      color: cs.primaryContainer,
      shape: const StadiumBorder(),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Cancel selection',
              color: fg,
              icon: const Icon(AppIcons.close),
              onPressed: _clearSelection,
            ),
            Expanded(
              child: Text(
                '${sel.length} selected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.titleMedium?.copyWith(color: fg),
              ),
            ),
            ...actions,
            PopupMenuButton<_Act>(
              tooltip: 'More',
              iconColor: fg,
              onSelected: (a) {
                if (a == _Act.selectAll) {
                  setState(() {
                    _selected
                      ..clear()
                      ..addAll(shown.map((n) => n.id));
                  });
                } else {
                  _apply(a, sel);
                }
              },
              itemBuilder: (_) => overflow,
            ),
          ],
        ),
      ),
    );
  }

  Widget _foldersGrid(List<NoteFolder> folders, int cols) {
    final rows = <Widget>[];
    for (var i = 0; i < folders.length; i += cols) {
      if (i > 0) rows.add(const SizedBox(height: Space.md));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < cols; c++) ...[
              if (c > 0) const SizedBox(width: Space.md),
              Expanded(
                child: (i + c) < folders.length
                    ? _FolderCard(
                        folder: folders[i + c],
                        count: widget.notes.noteCountInFolder(folders[i + c].id),
                        onTap: () => _openFolder(folders[i + c].id),
                        onNoteDropped: (note) => _moveNotesToFolder(
                          [note],
                          folders[i + c].id,
                          folderName: folders[i + c].name,
                        ),
                        onRename: () => _promptRenameFolder(folders[i + c]),
                        onDelete: () => _confirmDeleteFolder(folders[i + c]),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      sliver: SliverToBoxAdapter(
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }

  Widget _grid(List<Note> list, int cols, {bool isPinnedGrid = false}) {
    final columns = List.generate(cols, (_) => <Widget>[]);
    final canDrag = _section == _Section.notes && !_selecting;
    final cs = Theme.of(context).colorScheme;

    for (var i = 0; i < list.length; i++) {
      final n = list[i];
      final col = i % cols;
      if (columns[col].isNotEmpty) {
        columns[col].add(const SizedBox(height: Space.md));
      }

      final card = RepaintBoundary(
        child: _NoteCard(
          key: ValueKey(n.id),
          note: n,
          section: _section,
          selecting: _selecting,
          selected: _selected.contains(n.id),
          canMovePinUp: isPinnedGrid && i > 0,
          canMovePinDown: isPinnedGrid && i < list.length - 1,
          footer: _footer(n),
          editorBuilder: () => _editorFor(n),
          onOpenReduced: () => _openFade(n),
          onToggle: () => _toggle(n),
          onTrashedTap: () => unawaited(_trashedDialog(n)),
          onAction: (a) => _apply(a, [n]),
        ),
      );

      columns[col].add(
        canDrag
            ? LongPressDraggable<Note>(
                data: n,
                delay: const Duration(milliseconds: 220),
                onDragStarted: () => HapticFeedback.mediumImpact(),
                feedback: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(Radii.lg),
                  color: cs.surfaceContainerLowest,
                  child: Container(
                    width: 184,
                    padding: const EdgeInsets.all(Space.lg),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      border: Border.all(color: cs.primary, width: 1.5),
                    ),
                    child: Text(
                      n.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                childWhenDragging: Opacity(opacity: 0.35, child: card),
                child: card,
              )
            : card,
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      sliver: SliverToBoxAdapter(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < cols; c++) ...[
              if (c > 0) const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: columns[c],
                ),
              ),
            ],
          ],
        ),
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
    final reduce = Motion.reduced(context);

    return PopScope(
      canPop: !_selecting &&
          _query.isEmpty &&
          _selectedTag == null &&
          _activeFolderId == null &&
          _section == _Section.notes,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _drawer(context),
        floatingActionButton: _fab(
          cs,
          _section == _Section.notes && !_selecting,
          reduce,
        ),
        body: SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: Listenable.merge(
                [widget.notes, widget.bibles, widget.settings]),
            builder: (context, _) {
              final all = widget.notes.notes;
              final folders = widget.notes.folders;
              final trashedFolders = widget.notes.trashedFolders;
              final allTags = widget.notes.allTags;

              // Derive what is valid *now* instead of mutating state in build.
              // If the folder or tag vanished (deleted elsewhere), reset it
              // after this frame.
              final rawFolder = widget.notes.folderById(_activeFolderId);
              final activeFolder =
                  (rawFolder != null && !rawFolder.isTrashed) ? rawFolder : null;
              final folderId = activeFolder?.id;
              final tag = allTags.contains(_selectedTag) ? _selectedTag : null;
              if (folderId != _activeFolderId || tag != _selectedTag) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _activeFolderId = folderId;
                    _selectedTag = tag;
                  });
                });
              }

              final hint = switch (_section) {
                _Section.notes => activeFolder != null
                    ? 'Search in ${activeFolder.name}'
                    : 'Search your notes',
                _Section.archive => 'Search archive',
                _Section.trash => 'Search trash',
              };

              final inSection = _inSection(all);
              final q = _query.trim().toLowerCase();

              final List<Note> byFolder;
              if (_section == _Section.notes) {
                if (folderId != null) {
                  byFolder =
                      inSection.where((n) => n.folderId == folderId).toList();
                } else if (q.isEmpty && tag == null) {
                  byFolder =
                      inSection.where((n) => n.folderId == null).toList();
                } else {
                  byFolder = inSection;
                }
              } else {
                byFolder = inSection;
              }

              final byTag = tag == null
                  ? byFolder
                  : byFolder.where((n) => n.tags.contains(tag)).toList();

              final shown =
                  q.isEmpty ? byTag : byTag.where((n) => _matches(n, q)).toList();

              final showFolders = _section == _Section.notes &&
                  folderId == null &&
                  q.isEmpty &&
                  tag == null &&
                  folders.isNotEmpty;

              final showTrashedFolders = _section == _Section.trash &&
                  q.isEmpty &&
                  trashedFolders.isNotEmpty;

              final pinned = _section == _Section.notes
                  ? (shown.where((n) => n.pinned).toList()..sort(_cmpPinned))
                  : <Note>[];
              final others = (_section == _Section.notes
                      ? shown.where((n) => !n.pinned)
                      : shown)
                  .toList()
                ..sort(_cmp);

              final sel = all.where((n) => _selected.contains(n.id)).toList();

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Space.lg, Space.md, Space.lg, Space.sm),
                    // Mode swap happens constantly, so a quick crossfade only.
                    child: AnimatedSwitcher(
                      duration: reduce ? const Duration(milliseconds: 100) : Dur.fast,
                      child: _selecting
                          ? _selectionBar(cs, tt, sel, shown)
                          : _searchBar(
                              cs,
                              hint,
                              _section == _Section.notes && folderId == null,
                            ),
                    ),
                  ),
                  if (_section != _Section.trash && allTags.isNotEmpty)
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding:
                            const EdgeInsets.symmetric(horizontal: Space.lg),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: Space.sm),
                            child: FilterChip(
                              label: const Text('All'),
                              selected: tag == null,
                              onSelected: (_) =>
                                  setState(() => _selectedTag = null),
                            ),
                          ),
                          for (final t in allTags)
                            Padding(
                              padding: const EdgeInsets.only(right: Space.sm),
                              child: FilterChip(
                                label: Text('#$t'),
                                selected: tag == t,
                                onSelected: (on) =>
                                    setState(() => _selectedTag = on ? t : null),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: PageTransitionSwitcher(
                      duration: reduce
                          ? const Duration(milliseconds: 120)
                          : Dur.base,
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
                        key: ValueKey('$_section:$folderId'),
                        child: LayoutBuilder(
                          builder: (context, c) {
                            final cols = c.maxWidth < 520
                                ? 2
                                : (c.maxWidth < 820 ? 3 : 4);
                            return CustomScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: [
                                if (activeFolder != null)
                                  SliverToBoxAdapter(
                                    child: _FolderHeader(
                                      folder: activeFolder,
                                      count: shown.length,
                                      onBack: _exitFolder,
                                      onRename: () =>
                                          _promptRenameFolder(activeFolder),
                                      onDelete: () =>
                                          _confirmDeleteFolder(activeFolder),
                                      onDropToRoot: (note) =>
                                          _moveNotesToFolder([note], null),
                                    ),
                                  ),
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
                                          ? 'Notes and folders stay here until you delete them.'
                                          : 'Items are deleted forever after ${widget.settings.trashDays} days.',
                                      action: (inSection.isEmpty &&
                                              trashedFolders.isEmpty)
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
                                    child: _BibleBanner(
                                      isEmpty: widget.bibles.isEmpty,
                                      warnings: widget.bibles.warnings,
                                    ),
                                  ),
                                if (showFolders) ...[
                                  SliverToBoxAdapter(
                                    child: _SectionHeader(
                                      label: 'Folders',
                                      count: folders.length,
                                    ),
                                  ),
                                  _foldersGrid(folders, cols),
                                  const SliverToBoxAdapter(
                                      child: SizedBox(height: Space.md)),
                                ],
                                if (showTrashedFolders) ...[
                                  SliverToBoxAdapter(
                                    child: _SectionHeader(
                                      label: 'Trashed folders',
                                      count: trashedFolders.length,
                                    ),
                                  ),
                                  SliverPadding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: Space.lg),
                                    sliver: SliverList.separated(
                                      itemCount: trashedFolders.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: Space.sm),
                                      itemBuilder: (context, i) =>
                                          _TrashedFolderTile(
                                        folder: trashedFolders[i],
                                        onRestore: () async {
                                          final f = trashedFolders[i];
                                          await widget.notes.restoreFolder(f.id);
                                          _snack('Folder “${f.name}” restored');
                                        },
                                        onDeleteForever: () async {
                                          final f = trashedFolders[i];
                                          final ok = await _confirm(
                                            'Delete “${f.name}” forever?',
                                            'This folder and any trashed notes inside it will be permanently deleted.',
                                            'Delete forever',
                                          );
                                          if (ok) {
                                            await widget.notes
                                                .deleteFolderForever(f.id);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                  const SliverToBoxAdapter(
                                      child: SizedBox(height: Space.md)),
                                ],
                                if (shown.isEmpty &&
                                    !showFolders &&
                                    !showTrashedFolders)
                                  SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: _emptyState(
                                      q: q,
                                      tag: tag,
                                      activeFolder: activeFolder,
                                    ),
                                  ),
                                if (pinned.isNotEmpty) ...[
                                  SliverToBoxAdapter(
                                    child: _SectionHeader(
                                      label: 'Pinned',
                                      count: pinned.length,
                                      accent: true,
                                    ),
                                  ),
                                  _grid(pinned, cols, isPinnedGrid: true),
                                  const SliverToBoxAdapter(
                                      child: SizedBox(height: Space.lg)),
                                ],
                                if (others.isNotEmpty) ...[
                                  if (pinned.isNotEmpty ||
                                      showFolders ||
                                      showTrashedFolders)
                                    SliverToBoxAdapter(
                                      child: _SectionHeader(
                                        label: pinned.isNotEmpty
                                            ? 'Others'
                                            : 'Notes',
                                        count: others.length,
                                      ),
                                    ),
                                  _grid(others, cols),
                                ],
                                const SliverToBoxAdapter(
                                    child: SizedBox(height: _fabClearance)),
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

  Widget _emptyState({
    required String q,
    required String? tag,
    required NoteFolder? activeFolder,
  }) {
    final filtered = q.isNotEmpty || tag != null;
    final IconData icon;
    final String title;
    final String body;

    if (filtered) {
      icon = AppIcons.searchOff;
      title = q.isNotEmpty ? 'No results for “${_query.trim()}”' : 'No notes tagged #$tag';
      body = 'Try a different filter or word.';
    } else if (activeFolder != null) {
      icon = AppIcons.folderOpen;
      title = 'This folder is empty';
      body = 'Tap “New note” to add one here, or drag notes into this folder.';
    } else {
      switch (_section) {
        case _Section.notes:
          icon = AppIcons.bible;
          title = 'No notes yet';
          body =
              'Tap “New note”, then type a reference like James 1:2 and the verse appears.';
        case _Section.archive:
          icon = AppIcons.archive;
          title = 'Nothing archived';
          body = 'Archive notes you want to keep but not see every day.';
        case _Section.trash:
          icon = AppIcons.trash;
          title = 'Trash is empty';
          body = 'Deleted notes and folders show up here.';
      }
    }
    return _Empty(icon: icon, title: title, body: body);
  }
}

// --------------------------------------------------------------- small pieces

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({
    required this.title,
    required this.confirmLabel,
    this.initialValue = '',
  });

  final String title;
  final String confirmLabel;
  final String initialValue;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Folder name'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctl.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Shared drop surface for folder tiles and the open-folder header. Hover only
/// changes colour (not border width), so nothing shifts while dragging.
/// The InkWell sits on its own transparent Material *above* the decoration, so
/// the press ripple is actually visible.
class _NoteDropTarget extends StatelessWidget {
  const _NoteDropTarget({
    required this.accepts,
    required this.onDrop,
    required this.onTap,
    required this.builder,
    this.margin = EdgeInsets.zero,
  });

  final bool Function(Note) accepts;
  final ValueChanged<Note> onDrop;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;
  final Widget Function(bool hovering) builder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(Radii.lg);

    return DragTarget<Note>(
      onWillAcceptWithDetails: (d) => accepts(d.data),
      onAcceptWithDetails: (d) {
        HapticFeedback.mediumImpact();
        onDrop(d.data);
      },
      builder: (context, candidate, _) {
        final hovering = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: Dur.fast,
          margin: margin,
          decoration: BoxDecoration(
            color: hovering ? cs.primaryContainer : cs.surfaceContainerLowest,
            borderRadius: radius,
            border: Border.all(
              color: hovering ? cs.primary : cs.outlineVariant,
            ),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap, child: builder(hovering)),
            ),
          ),
        );
      },
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
    required this.folder,
    required this.count,
    required this.onTap,
    required this.onNoteDropped,
    required this.onRename,
    required this.onDelete,
  });

  final NoteFolder folder;
  final int count;
  final VoidCallback onTap;
  final ValueChanged<Note> onNoteDropped;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return _NoteDropTarget(
      accepts: (n) => n.folderId != folder.id,
      onDrop: onNoteDropped,
      onTap: onTap,
      builder: (hovering) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.xs, Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Icon(
                    hovering ? AppIcons.folderOpen : AppIcons.folder,
                    size: 32,
                    color: cs.primary,
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'Folder options',
                  icon: Icon(AppIcons.more,
                      size: 20, color: cs.onSurfaceVariant),
                  onSelected: (v) {
                    if (v == 'rename') onRename();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete folder',
                          style: TextStyle(color: cs.error)),
                    ),
                  ],
                ),
              ],
            ),
            Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              count == 1 ? '1 note' : '$count notes',
              style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderHeader extends StatelessWidget {
  const _FolderHeader({
    required this.folder,
    required this.count,
    required this.onBack,
    required this.onRename,
    required this.onDelete,
    required this.onDropToRoot,
  });

  final NoteFolder folder;
  final int count;
  final VoidCallback onBack;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final ValueChanged<Note> onDropToRoot;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return _NoteDropTarget(
      accepts: (n) => n.folderId != null,
      onDrop: onDropToRoot,
      onTap: null,
      margin: const EdgeInsets.fromLTRB(
          Space.lg, Space.sm, Space.lg, Space.sm),
      builder: (hovering) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back to all notes',
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
            ),
            Icon(
              hovering ? AppIcons.folderOutput : AppIcons.folderOpen,
              size: 24,
              color: cs.primary,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hovering ? 'Drop to move out of folder' : folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    count == 1 ? '1 note' : '$count notes',
                    style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Folder options',
              icon: Icon(AppIcons.more, color: cs.onSurfaceVariant),
              onSelected: (v) {
                if (v == 'rename') onRename();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(
                  value: 'delete',
                  child:
                      Text('Delete folder', style: TextStyle(color: cs.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrashedFolderTile extends StatelessWidget {
  const _TrashedFolderTile({
    required this.folder,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final NoteFolder folder;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: ListTile(
        leading: Icon(AppIcons.folder, color: cs.outline),
        title: Text(folder.name),
        subtitle: Text('Deleted ${_when(folder.deletedAt ?? folder.createdAt)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Restore folder',
              icon: const Icon(AppIcons.restore),
              onPressed: onRestore,
            ),
            IconButton(
              tooltip: 'Delete forever',
              icon: Icon(AppIcons.deleteForever, color: cs.error),
              onPressed: onDeleteForever,
            ),
          ],
        ),
      ),
    );
  }
}

/// Setup problems are for the developer; end users just see that no Bible is
/// available. The file-path hint only shows in debug builds.
class _BibleBanner extends StatelessWidget {
  const _BibleBanner({required this.isEmpty, required this.warnings});

  final bool isEmpty;
  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(color: cs.onErrorContainer);
    return Container(
      margin: const EdgeInsets.fromLTRB(
          Space.lg, Space.sm, Space.lg, Space.sm),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEmpty
                ? (kDebugMode
                    ? 'No Bible loaded. Put your XML files in assets/bibles/ and rebuild.'
                    : 'No Bible is available. Verses will not appear in your notes.')
                : 'Some Bible files could not be loaded.',
            style: style,
          ),
          if (kDebugMode)
            for (final w in warnings) Text('• $w', style: style),
        ],
      ),
    );
  }
}

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
        excludeFromSemantics: true,
        errorBuilder: (context, error, stack) => Container(
          width: size,
          height: size,
          color: cs.primaryContainer,
          alignment: Alignment.center,
          child: Icon(
            AppIcons.bible,
            size: size * 0.6,
            color: cs.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

/// Plain section label with a muted count. Left-aligned to the card edge.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    this.accent = false,
  });

  final String label;
  final int count;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Space.lg, Space.lg, Space.lg, Space.sm),
      child: Text.rich(
        TextSpan(
          text: label,
          style: tt.titleSmall?.copyWith(
            color: accent ? cs.primary : cs.onSurface,
            fontWeight: FontWeight.w600,
          ),
          children: [
            TextSpan(
              text: '  $count',
              style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
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
      padding: const EdgeInsets.fromLTRB(
          Space.lg, Space.md, Space.sm, Space.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tt.headlineSmall),
                const SizedBox(height: Space.xs),
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

/// Empty states are seen often, so they just fade in. No translate, no spring.
class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: cs.outline),
            const SizedBox(height: Space.lg),
            Text(title, style: tt.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: Space.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
    if (Motion.reduced(context)) return content;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Dur.base,
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(opacity: v, child: child),
      child: content,
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
    this.canMovePinUp = false,
    this.canMovePinDown = false,
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
  final bool canMovePinUp;
  final bool canMovePinDown;
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
            Icon(icon, size: 20, color: color),
            const SizedBox(width: Space.md),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      );

  List<PopupMenuEntry<_Act>> _menu(ColorScheme cs) {
    switch (section) {
      case _Section.notes:
        return [
          _item(_Act.select, AppIcons.checked, 'Select'),
          note.pinned
              ? _item(_Act.unpin, AppIcons.unpin, 'Unpin')
              : _item(_Act.pin, AppIcons.pin, 'Pin'),
          if (note.pinned && canMovePinUp)
            _item(_Act.movePinUp, AppIcons.arrowUp, 'Move pin earlier'),
          if (note.pinned && canMovePinDown)
            _item(_Act.movePinDown, AppIcons.arrowDown, 'Move pin later'),
          _item(_Act.moveToFolder, AppIcons.folder, 'Move to folder'),
          if (note.folderId != null)
            _item(_Act.removeFromFolder, AppIcons.folderOutput,
                'Remove from folder'),
          _item(_Act.archive, AppIcons.archive, 'Archive'),
          _item(_Act.trash, AppIcons.trash, 'Delete', color: cs.error),
        ];
      case _Section.archive:
        return [
          _item(_Act.unarchive, AppIcons.unarchive, 'Unarchive'),
          _item(_Act.trash, AppIcons.trash, 'Delete', color: cs.error),
        ];
      case _Section.trash:
        return [
          _item(_Act.restore, AppIcons.restore, 'Restore'),
          _item(_Act.deleteForever, AppIcons.deleteForever, 'Delete forever',
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

    // One state, one signal: selection gets the tint + border + checkmark.
    // Pinned is shown by its pin icon and section header only.
    final Color fill = selected
        ? Color.alphaBlend(
            cs.primaryContainer.withValues(alpha: 0.6),
            cs.surfaceContainerLowest)
        : cs.surfaceContainerLowest;

    final side = BorderSide(
      color: selected ? cs.primary : cs.outlineVariant,
      width: 1.5,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.lg),
      side: side,
    );
    final openShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
      side: side,
    );

    return Semantics(
      selected: selected,
      child: PressScale(
        child: OpenContainer<void>(
          closedColor: fill,
          openColor: cs.surface,
          middleColor: cs.surface,
          closedElevation: 0,
          openElevation: 0,
          closedShape: shape,
          openShape: openShape,
          transitionDuration: Dur.route,
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
            onLongPress: section == _Section.notes && !selecting
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    onToggle();
                  },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.lg - 1),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Space.lg, Space.md, Space.xs, Space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(
                                top: Space.sm, right: Space.xs),
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
                            padding: const EdgeInsets.fromLTRB(
                                0, Space.md, Space.md, 0),
                            child: AnimatedSwitcher(
                              duration: reduce
                                  ? const Duration(milliseconds: 100)
                                  : Dur.fast,
                              switchInCurve: Curves.easeOutCubic,
                              transitionBuilder: (c, a) => reduce
                                  ? FadeTransition(opacity: a, child: c)
                                  : ScaleTransition(
                                      scale: Tween<double>(begin: 0.8, end: 1)
                                          .animate(a),
                                      child: FadeTransition(opacity: a, child: c),
                                    ),
                              child: Icon(
                                selected
                                    ? AppIcons.checked
                                    : AppIcons.unchecked,
                                key: ValueKey(selected),
                                size: 24,
                                color: selected ? cs.primary : cs.outline,
                              ),
                            ),
                          )
                        else ...[
                          if (note.pinned)
                            Padding(
                              padding: const EdgeInsets.only(top: Space.md),
                              child: Icon(AppIcons.pin,
                                  size: 16, color: cs.primary),
                            ),
                          PopupMenuButton<_Act>(
                            tooltip: 'Note options',
                            icon: Icon(AppIcons.more,
                                size: 20, color: cs.onSurfaceVariant),
                            onSelected: onAction,
                            itemBuilder: (_) => _menu(cs),
                          ),
                        ],
                      ],
                    ),
                    if (note.preview.trim().isNotEmpty) ...[
                      const SizedBox(height: Space.xs),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(right: Space.md),
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
                    if (note.tags.isNotEmpty) ...[
                      const SizedBox(height: Space.md),
                      Padding(
                        padding: const EdgeInsets.only(right: Space.md),
                        child: Wrap(
                          spacing: Space.xs + 2,
                          runSpacing: Space.xs,
                          children: [
                            for (final t in note.tags.take(4))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: Space.sm, vertical: Space.xs / 2),
                                decoration: BoxDecoration(
                                  color: cs.secondaryContainer,
                                  borderRadius: BorderRadius.circular(Radii.sm),
                                ),
                                child: Text(
                                  '#$t',
                                  style: tt.labelMedium?.copyWith(
                                    color: cs.onSecondaryContainer,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.md),
                    Text(
                      footer,
                      style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
          openBuilder: (context, _) => editorBuilder(),
        ),
      ),
    );
  }
}