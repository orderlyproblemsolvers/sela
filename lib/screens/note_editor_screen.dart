import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../bible/bible_repository.dart';
import '../bible/verse_ref.dart';
import '../motion.dart';
import '../notes/note.dart';
import '../notes/note_store.dart';
import '../notes/settings_store.dart';
import '../widgets/verse_embed.dart';

/// Quill shows every embed as this character in plain text.
const String _obj = '\uFFFC';

/// Typing one of these right after a reference (e.g. "James 2:1 ")
/// triggers the verse lookup.
const Set<String> _triggers = {' ', '\u00A0', ',', '.', ';', '!', '?', ')'};

/// A stretch of note text that is scripture.
class _VerseRun {
  _VerseRun(this.start, this.end, this.link);

  final int start;
  int end;
  final VerseLink link;
}

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    required this.note,
    required this.notes,
    required this.bibles,
    required this.settings,
  });

  final Note note;
  final NoteStore notes;
  final BibleRepository bibles;
  final SettingsStore settings;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final QuillController _controller;
  late final StreamSubscription<DocChange> _sub;
  late final TextEditingController _titleCtl;
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;
  bool _dirty = false;

  /// Our own edits fire document events too; ignore them briefly.
  DateTime _suppressUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    Document doc;
    try {
      doc = widget.note.delta.isEmpty
          ? Document()
          : Document.fromJson(widget.note.delta);
    } catch (_) {
      doc = Document();
    }
    _controller = QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _titleCtl = TextEditingController(text: widget.note.title);
    _sub = _controller.document.changes.listen(_onDocChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub.cancel();
    _controller.dispose();
    _titleCtl.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- saving

  void _markDirty() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _save);
  }

  void _onDocChange(DocChange event) {
    _markDirty();
    _maybeEmbedVerse(event);
  }

  void _togglePin() {
    HapticFeedback.selectionClick();
    setState(() {
      widget.note.pinned = !widget.note.pinned;
      if (widget.note.pinned) widget.note.archived = false;
    });
    _markDirty();
  }

  Future<void> _save() async {
    if (!_dirty) return;
    _dirty = false;

    final title = _titleCtl.text.trim();
    final plain =
        _controller.document.toPlainText().replaceAll(_obj, '').trim();
    final isNew = !widget.notes.contains(widget.note.id);
    if (plain.isEmpty && title.isEmpty && isNew) return; // don't save empty

    String clip(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';

    final note = widget.note;
    note.title = title;
    note.plain = plain;
    note.preview = clip(plain.replaceAll(RegExp(r'\n{2,}'), '\n'), 280);
    note.delta = _controller.document.toDelta().toJson();
    note.updatedAt = DateTime.now();
    await widget.notes.save(note);
  }

  /// Archive / delete from inside the editor.
  Future<void> _onMenu(String action) async {
    _debounce?.cancel();
    await _save();
    if (!mounted) return;

    final notes = widget.notes;
    final note = widget.note;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    if (!notes.contains(note.id)) {
      nav.pop(); // never saved (empty), nothing to archive or delete
      return;
    }

    if (action == 'archive') {
      final was = note.archived;
      await notes.setArchived([note], !was);
      nav.pop();
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(was ? 'Note unarchived' : 'Note archived'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => notes.setArchived([note], was),
          ),
        ));
    } else {
      await notes.trash([note]);
      nav.pop();
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: const Text('Note moved to Trash'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => notes.restore([note]),
          ),
        ));
    }
  }

  // ------------------------------------------------------- verse text/runs

  /// What gets written into the note for [ref].
  String _verseText(BibleVersion? bible, VerseRef ref, bool open) {
    if (!open || bible == null) return ref.label;
    final multi = ref.verseEnd > ref.verseStart;
    final parts = <String>[];
    for (var v = ref.verseStart; v <= ref.verseEnd; v++) {
      final t = bible.verse(ref.book, ref.chapter, v);
      if (t != null) parts.add(multi ? '$v $t' : t);
    }
    if (parts.isEmpty) return ref.label;
    return '“${parts.join(' ')}” (${ref.label})';
  }

  /// All scripture runs in the note, found from the document's delta.
  List<_VerseRun> _verseRuns() {
    final out = <_VerseRun>[];
    var off = 0;
    for (final op in _controller.document.toDelta().toList()) {
      final d = op.data;
      final len = d is String ? d.length : 1;
      final raw = op.attributes?['link'];
      if (raw is String && raw.startsWith(kVerseLinkScheme)) {
        final link = VerseLink.tryParse(raw);
        if (link != null) {
          if (out.isNotEmpty &&
              out.last.end == off &&
              out.last.link.url == link.url) {
            out.last.end = off + len;
          } else {
            out.add(_VerseRun(off, off + len, link));
          }
        }
      }
      off += len;
    }
    return out;
  }

  _VerseRun? _runAtSelection() {
    final sel = _controller.selection;
    if (!sel.isValid) return null;
    final a = sel.start;
    final b = sel.end;
    for (final r in _verseRuns()) {
      if (sel.isCollapsed) {
        if (a > r.start && a <= r.end) return r;
      } else if (a < r.end && b > r.start) {
        return r;
      }
    }
    return null;
  }

  /// Replaces [len] characters at [start] with the verse text and marks it as
  /// scripture. Returns the length of the text written.
  int _writeVerse(
    VerseRef ref,
    bool open,
    int start,
    int len,
    int Function(int textLen) cursorAt,
  ) {
    final bible = widget.bibles.version(ref.version);
    final text = _verseText(bible, ref, open);
    _suppressUntil = DateTime.now().add(const Duration(milliseconds: 250));
    _controller.replaceText(
      start,
      len,
      text,
      TextSelection.collapsed(offset: cursorAt(text.length)),
    );
    _controller.formatText(
      start,
      text.length,
      LinkAttribute(VerseLink(ref, open).url),
    );
    return text.length;
  }

  // --------------------------------------------------- auto verse detection

  /// First plain-text insertion in [change] as (position, text).
  (int, String)? _firstTextInsert(Delta change) {
    var pos = 0;
    for (final op in change.toList()) {
      if (op.isRetain) {
        pos += op.length ?? 0;
      } else if (op.isInsert) {
        final d = op.data;
        if (d is String) return (pos, d);
        pos += 1; // an embed
      }
    }
    return null;
  }

  void _maybeEmbedVerse(DocChange event) {
    if (!widget.settings.autoInsertVerses) return;
    if (DateTime.now().isBefore(_suppressUntil)) return;

    final ins = _firstTextInsert(event.change);
    if (ins == null) return;
    final (pos, typed) = ins;
    if (typed.isEmpty) return;
    final lastChar = typed[typed.length - 1];
    if (!_triggers.contains(lastChar)) return;

    final bible = widget.bibles.version(null);
    if (bible == null) return; // no Bible loaded yet

    final t = _controller.document.toPlainText();
    final lastIdx = pos + typed.length - 1;
    if (lastIdx <= 0 || lastIdx >= t.length || t[lastIdx] != lastChar) return;

    final lineStart = t.lastIndexOf('\n', lastIdx - 1) + 1;
    final hit = matchReferenceAtEnd(t.substring(lineStart, lastIdx));
    if (hit == null) return;
    final (parsed, relStart) = hit;
    if (bible.verse(parsed.book, parsed.chapter, parsed.verseStart) == null) {
      return; // not a real verse in the loaded Bible
    }

    final refStart = lineStart + relStart;

    // Don't convert text that is already inside a verse.
    for (final r in _verseRuns()) {
      if (r.start < lastIdx && r.end > refStart) return;
    }

    // Replace the typed reference with the scripture; keep the typed
    // space/punctuation after it and put the cursor after that.
    _writeVerse(
      parsed.withVersion(bible.id),
      widget.settings.insertExpanded,
      refStart,
      lastIdx - refStart,
      (n) => refStart + n + 1,
    );
  }

  // --------------------------------------------------------- verse actions

  void _rewrite(_VerseRun run, {bool? open, String? version}) {
    HapticFeedback.selectionClick();
    final ref = run.link.ref.withVersion(
        version ?? run.link.ref.version ?? widget.bibles.selectedId);
    _writeVerse(
      ref,
      open ?? run.link.open,
      run.start,
      run.end - run.start,
      (_) => run.start + 1,
    );
  }

  void _unlink(_VerseRun run) {
    _suppressUntil = DateTime.now().add(const Duration(milliseconds: 250));
    _controller.formatText(
        run.start, run.end - run.start, LinkAttribute(null));
  }

  Future<void> _pickVersion(_VerseRun run) async {
    final ids = widget.bibles.versionIds;
    if (ids.length < 2) return;
    final current = run.link.ref.version;

    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Show ${run.link.ref.label} in…',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final id in ids)
                    ListTile(
                      title: Text(id),
                      trailing: id == current ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.pop(ctx, id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (picked == null || !mounted) return;
    _rewrite(_runAtSelection() ?? run, version: picked);
  }

  /// The bar slides/fades in like a sheet (critically-damped spring), and
  /// its icons morph instead of snapping.
  Widget _verseBar(ColorScheme cs) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final reduce = Motion.reduced(context);
        final run = _runAtSelection();
        return AnimatedSwitcher(
          duration: Duration(milliseconds: reduce ? 120 : 420),
          reverseDuration: Duration(milliseconds: reduce ? 100 : 260),
          switchInCurve: const SpringCurve(),
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, a) => reduce
              ? FadeTransition(opacity: a, child: child)
              : ClipRect(
                  child: SizeTransition(
                    sizeFactor: a,
                    axisAlignment: -1,
                    child: FadeTransition(opacity: a, child: child),
                  ),
                ),
          child: run == null
              ? const SizedBox.shrink(key: ValueKey('no-verse'))
              : _verseBarBody(cs, run, reduce),
        );
      },
    );
  }

  Widget _morph(bool reduce, Widget icon) => AnimatedSwitcher(
        duration: Duration(milliseconds: reduce ? 80 : 260),
        switchInCurve: const SpringCurve(duration: Duration(milliseconds: 260)),
        transitionBuilder: (c, a) => reduce
            ? FadeTransition(opacity: a, child: c)
            : RotationTransition(
                turns: Tween<double>(begin: 0.12, end: 0).animate(a),
                child: ScaleTransition(
                  scale: a,
                  child: FadeTransition(opacity: a, child: c),
                ),
              ),
        child: icon,
      );

  Widget _verseBarBody(ColorScheme cs, _VerseRun run, bool reduce) {
    final ref = run.link.ref;
    final version = ref.version ?? widget.bibles.selectedId ?? '';
    final canSwitch = widget.bibles.versionIds.length > 1;

    return Material(
      key: const ValueKey('verse-bar'),
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.only(left: 20, right: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                version.isEmpty ? ref.label : '${ref.label}  ·  $version',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.onSecondaryContainer,
                ),
              ),
            ),
            if (canSwitch)
              IconButton(
                tooltip: 'Change translation',
                icon: const Icon(Icons.translate),
                onPressed: () => _pickVersion(run),
              ),
            IconButton(
              tooltip: run.link.open ? 'Collapse verse' : 'Expand verse',
              icon: _morph(
                reduce,
                Icon(
                  run.link.open ? Icons.unfold_less : Icons.unfold_more,
                  key: ValueKey(run.link.open),
                ),
              ),
              onPressed: () => _rewrite(run, open: !run.link.open),
            ),
            IconButton(
              tooltip: 'Remove verse styling (keep text)',
              icon: const Icon(Icons.link_off),
              onPressed: () => _unlink(run),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------- manual insertion

  Future<void> _promptInsertVerse() async {
    final bible = widget.bibles.version(null);
    if (bible == null) {
      _toast('No Bible loaded. Add XML files to assets/bibles/.');
      return;
    }
    final input = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Insert verse'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. James 2:1  or  John 3:16-18',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, input.text),
              child: const Text('Insert')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;

    final parsed = parseReference(text.trim());
    if (parsed == null ||
        bible.verse(parsed.book, parsed.chapter, parsed.verseStart) == null) {
      _toast('Couldn’t find “${text.trim()}” in ${bible.id}.');
      return;
    }

    final maxIdx = _controller.document.length - 1;
    final sel = _controller.selection;
    var start = sel.isValid ? sel.start : maxIdx;
    if (start < 0 || start > maxIdx) start = maxIdx;
    var len = sel.isValid ? sel.end - sel.start : 0;
    if (start + len > maxIdx) len = maxIdx - start;

    final n = _writeVerse(
      parsed.withVersion(bible.id),
      widget.settings.insertExpanded,
      start,
      len,
      (n) => start + n,
    );

    // A plain space after the verse so typing continues as normal text.
    _controller.replaceText(
      start + n,
      0,
      ' ',
      TextSelection.collapsed(offset: start + n + 1),
    );
    _controller.formatText(start + n, 1, LinkAttribute(null));
    _focus.requestFocus();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isNew = widget.note.title.isEmpty && widget.note.delta.isEmpty;

    // Apply the user's text-size setting on top of the system one.
    final media = MediaQuery.of(context);
    final scaler = TextScaler.linear(
        media.textScaler.scale(1.0) * widget.settings.editorScale);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_save());
      },
      child: Scaffold(
        appBar: AppBar(
          actions: [
            ListenableBuilder(
              listenable: widget.bibles,
              builder: (context, _) {
                final ids = widget.bibles.versionIds;
                if (ids.isEmpty) return const SizedBox.shrink();
                return PopupMenuButton<String>(
                  tooltip: 'Bible version for new verses',
                  initialValue: widget.bibles.selectedId,
                  onSelected: widget.bibles.select,
                  itemBuilder: (_) => [
                    for (final id in ids)
                      PopupMenuItem(value: id, child: Text(id)),
                  ],
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Text(
                      '${widget.bibles.selectedId ?? ''} ▾',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: widget.note.pinned ? 'Unpin' : 'Pin',
              icon: _morph(
                Motion.reduced(context),
                Icon(
                  widget.note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  key: ValueKey(widget.note.pinned),
                  color: widget.note.pinned ? cs.primary : null,
                ),
              ),
              onPressed: _togglePin,
            ),
            IconButton(
              tooltip: 'Insert verse',
              icon: const Icon(Icons.menu_book_outlined),
              onPressed: _promptInsertVerse,
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: _onMenu,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'archive',
                  child: Row(
                    children: [
                      Icon(
                          widget.note.archived
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                          size: 18),
                      const SizedBox(width: 10),
                      Text(widget.note.archived ? 'Unarchive' : 'Archive'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'trash',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: cs.error),
                      const SizedBox(width: 10),
                      Text('Delete', style: TextStyle(color: cs.error)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: TextField(
                  controller: _titleCtl,
                  autofocus: isNew,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _markDirty(),
                  onSubmitted: (_) => _focus.requestFocus(),
                  maxLines: null,
                  style: tt.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Title',
                    hintStyle: tt.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: cs.outline,
                    ),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: MediaQuery(
                    data: media.copyWith(textScaler: scaler),
                    child: QuillEditor.basic(
                      controller: _controller,
                      focusNode: _focus,
                      scrollController: _scroll,
                      config: QuillEditorConfig(
                        placeholder:
                            'Start typing…  try “just like in James 2:1 ”',
                        padding: const EdgeInsets.only(top: 8, bottom: 80),
                        // Scripture = text with a "verse:" link: same colour
                        // as your text, dotted underline.
                        customStyles: DefaultStyles(
                          link: TextStyle(
                            decoration: TextDecoration.underline,
                            decorationStyle: TextDecorationStyle.dotted,
                            decorationColor: cs.primary,
                            decorationThickness: 1.5,
                          ),
                        ),
                        onLaunchUrl: (_) {}, // verse links aren't web links
                        embedBuilders: [VerseEmbedBuilder()],
                      ),
                    ),
                  ),
                ),
              ),
              _verseBar(cs),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: cs.outlineVariant)),
                ),
                child: QuillSimpleToolbar(
                  controller: _controller,
                  config: const QuillSimpleToolbarConfig(
                    multiRowsDisplay: false,
                    showFontFamily: false,
                    showSearchButton: false,
                    showSubscript: false,
                    showSuperscript: false,
                    showInlineCode: false,
                    showCodeBlock: false,
                    showSmallButton: false,
                    showLink: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
