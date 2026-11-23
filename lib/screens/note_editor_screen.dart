import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../app_icons.dart';
import '../bible/bible_repository.dart';
import '../bible/verse_ref.dart';
import '../motion.dart';
import '../notes/note.dart';
import '../notes/note_io.dart';
import '../notes/note_store.dart';
import '../notes/settings_store.dart';
import '../tokens.dart';
import '../widgets/verse_embed.dart';

const String _obj = '\uFFFC';
const Set<String> _triggers = {' ', '\u00A0', ',', '.', ';', '!', '?', ')'};

/// Widest the writing column grows, so lines stay readable on tablets/desktop.
const double _maxEditorWidth = 720;

String _slug(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

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
  // Mid-tone text colours that stay readable (about 3:1 or better) on both
  // the light and dark surfaces. Existing notes keep whatever hex they stored.
  static const _textColors = <(String, String, Color)>[
    ('Teal', '#3F8F8A', Color(0xFF3F8F8A)),
    ('Crimson', '#C0392B', Color(0xFFC0392B)),
    ('Ochre', '#B7791F', Color(0xFFB7791F)),
    ('Forest', '#2E7D32', Color(0xFF2E7D32)),
    ('Ocean', '#1D6FA5', Color(0xFF1D6FA5)),
    ('Plum', '#7B3FA0', Color(0xFF7B3FA0)),
    ('Muted', '#7C8583', Color(0xFF7C8583)),
  ];

  static const _highlightColors = <(String, String, Color)>[
    ('Yellow', '#FEF08A', Color(0xFFFEF08A)),
    ('Peach', '#FED7AA', Color(0xFFFED7AA)),
    ('Rose', '#FECDD3', Color(0xFFFECDD3)),
    ('Mint', '#BBF7D0', Color(0xFFBBF7D0)),
    ('Sky', '#BAE6FD', Color(0xFFBAE6FD)),
    ('Lavender', '#E9D5FF', Color(0xFFE9D5FF)),
    ('Stone', '#DCE1DF', Color(0xFFDCE1DF)),
  ];

  late final QuillController _controller;
  late final StreamSubscription<DocChange> _sub;
  late final TextEditingController _titleCtl;
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;
  bool _dirty = false;

  /// Controls the parallel translation comparison panel in the verse bar.
  bool _comparing = false;
  String? _compareVersionId;

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
    if (_maybeApplyMarkdownShortcut(event)) return;
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
    if (plain.isEmpty && title.isEmpty && isNew) return;

    String clip(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';

    final note = widget.note;
    note.title = title;
    note.plain = plain;
    note.preview = clip(plain.replaceAll(RegExp(r'\n{2,}'), '\n'), 280);
    note.delta = _controller.document.toDelta().toJson();
    note.updatedAt = DateTime.now();
    note.refreshTags();
    await widget.notes.save(note);
  }

  Future<void> _onMenu(String action) async {
    _debounce?.cancel();
    await _save();
    if (!mounted) return;

    final notes = widget.notes;
    final note = widget.note;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    if (action == 'export_md') {
      await NoteIO.saveOrShareFile(
        context: context,
        fileName: '${_slug(note.displayTitle)}.md',
        bytes: Uint8List.fromList(utf8.encode(NoteIO.toMarkdown(note))),
        mimeType: 'text/markdown',
      );
      return;
    }

    if (action == 'export_pdf') {
      final pdfBytes = await NoteIO.toPdfBytes(note);
      if (!mounted) return;
      await NoteIO.saveOrShareFile(
        context: context,
        fileName: '${_slug(note.displayTitle)}.pdf',
        bytes: pdfBytes,
        mimeType: 'application/pdf',
      );
      return;
    }

    if (!notes.contains(note.id)) {
      nav.pop();
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
    } else if (action == 'trash') {
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

  // --------------------------------------------------- preset color picker

  Future<void> _pickFormatColor({required bool isBackground}) async {
    final tt = Theme.of(context).textTheme;
    final palette = isBackground ? _highlightColors : _textColors;
    final attrKey = isBackground ? 'background' : 'color';
    final current = (_controller.getSelectionStyle().attributes[attrKey]?.value
            as String?)
        ?.toLowerCase();

    final picked = await showModalBottomSheet<String?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              Space.lg, Space.xs, Space.lg, Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isBackground ? 'Highlight color' : 'Text color',
                style: tt.titleLarge,
              ),
              const SizedBox(height: Space.lg),
              Wrap(
                spacing: Space.md,
                runSpacing: Space.md,
                children: [
                  _Swatch(
                    label: isBackground ? 'No highlight' : 'Default text',
                    selected: current == null,
                    onTap: () => Navigator.pop(ctx, ''),
                  ),
                  for (final (label, hex, color) in palette)
                    _Swatch(
                      label: label,
                      color: color,
                      selected: current == hex.toLowerCase(),
                      onTap: () => Navigator.pop(ctx, hex),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (picked == null || !mounted) return;
    final attr =
        Attribute.fromKeyValue(attrKey, picked.isEmpty ? null : picked);
    _controller.formatSelection(attr);
  }

  // --------------------------------------------------- markdown shortcuts

  bool _maybeApplyMarkdownShortcut(DocChange event) {
    if (DateTime.now().isBefore(_suppressUntil)) return false;
    final ins = _firstTextInsert(event.change);
    if (ins == null) return false;
    final (pos, typed) = ins;
    if (typed != ' ') return false;

    final plain = _controller.document.toPlainText();
    if (pos <= 0 || pos >= plain.length) return false;

    final lineStart = plain.lastIndexOf('\n', pos - 1) + 1;
    final linePrefix = plain.substring(lineStart, pos);

    // Block-level Markdown shortcuts at the start of a line
    Attribute? blockAttr;
    switch (linePrefix) {
      case '#':
        blockAttr = Attribute.h1;
      case '##':
        blockAttr = Attribute.h2;
      case '###':
        blockAttr = Attribute.h3;
      case '-':
      case '*':
        blockAttr = Attribute.ul;
      case '1.':
        blockAttr = Attribute.ol;
      case '[]':
      case '[ ]':
        blockAttr = Attribute.unchecked;
      case '[x]':
      case '[X]':
        blockAttr = Attribute.checked;
      case '>':
        blockAttr = Attribute.blockQuote;
    }

    if (blockAttr != null) {
      _suppressUntil = DateTime.now().add(const Duration(milliseconds: 200));
      final removeLen = (pos - lineStart) + 1; // prefix + space
      _controller.replaceText(
        lineStart,
        removeLen,
        '',
        TextSelection.collapsed(offset: lineStart),
      );
      _controller.formatText(lineStart, 0, blockAttr);
      return true;
    }

    // Inline Markdown shortcuts: **bold** or *italic* followed by space
    final boldMatch = RegExp(r'\*\*(.+?)\*\*$').firstMatch(linePrefix);
    if (boldMatch != null) {
      final inner = boldMatch.group(1)!;
      final matchStart = lineStart + boldMatch.start;
      final matchLen = boldMatch.group(0)!.length;
      _suppressUntil = DateTime.now().add(const Duration(milliseconds: 200));
      _controller.replaceText(
        matchStart,
        matchLen,
        inner,
        TextSelection.collapsed(offset: matchStart + inner.length + 1),
      );
      _controller.formatText(matchStart, inner.length, Attribute.bold);
      return true;
    }

    final italicMatch = RegExp(r'(?<!\*)\*([^*]+?)\*$').firstMatch(linePrefix);
    if (italicMatch != null) {
      final inner = italicMatch.group(1)!;
      final matchStart = lineStart + italicMatch.start;
      final matchLen = italicMatch.group(0)!.length;
      _suppressUntil = DateTime.now().add(const Duration(milliseconds: 200));
      _controller.replaceText(
        matchStart,
        matchLen,
        inner,
        TextSelection.collapsed(offset: matchStart + inner.length + 1),
      );
      _controller.formatText(matchStart, inner.length, Attribute.italic);
      return true;
    }

    return false;
  }

  // ------------------------------------------------------- verse text/runs

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

  (int, String)? _firstTextInsert(Delta change) {
    var pos = 0;
    for (final op in change.toList()) {
      if (op.isRetain) {
        pos += op.length ?? 0;
      } else if (op.isInsert) {
        final d = op.data;
        if (d is String) return (pos, d);
        pos += 1;
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
    if (bible == null) return;

    final t = _controller.document.toPlainText();
    final lastIdx = pos + typed.length - 1;
    if (lastIdx <= 0 || lastIdx >= t.length || t[lastIdx] != lastChar) return;

    final lineStart = t.lastIndexOf('\n', lastIdx - 1) + 1;
    final hit = matchReferenceAtEnd(t.substring(lineStart, lastIdx));
    if (hit == null) return;
    final (parsed, relStart) = hit;
    if (bible.verse(parsed.book, parsed.chapter, parsed.verseStart) == null) {
      return;
    }

    final refStart = lineStart + relStart;
    for (final r in _verseRuns()) {
      if (r.start < lastIdx && r.end > refStart) return;
    }

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
              padding:
                  const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
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
                      trailing:
                          id == current ? const Icon(AppIcons.check) : null,
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

  /// The bar changes the editor's height, so it eases without overshoot;
  /// a bouncing layout would make the text jitter.
  Widget _verseBar(ColorScheme cs) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final reduce = Motion.reduced(context);
        final run = _runAtSelection();
        return AnimatedSwitcher(
          duration: reduce ? const Duration(milliseconds: 100) : Dur.base,
          reverseDuration: reduce ? const Duration(milliseconds: 100) : Dur.fast,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, a) => reduce
              ? FadeTransition(opacity: a, child: child)
              : ClipRect(
                  child: SizeTransition(
                    sizeFactor: a,
                    alignment: Alignment.topCenter,
                    child: FadeTransition(opacity: a, child: child),
                  ),
                ),
          child: run == null
              ? const SizedBox.shrink(key: ValueKey('no-verse'))
              : _verseBarBody(cs, run),
        );
      },
    );
  }

  /// Icon swap for toggles (expand/collapse, pin): a quick crossfade only.
  Widget _swap(Widget icon) => AnimatedSwitcher(
        duration: Dur.fast,
        child: icon,
      );

  Widget _verseBarBody(ColorScheme cs, _VerseRun run) {
    final ref = run.link.ref;
    final ids = widget.bibles.versionIds;
    final version = ref.version ?? widget.bibles.selectedId ?? '';
    final canSwitch = ids.length > 1;

    // Default secondary version for parallel comparison
    final altId = (_compareVersionId != null &&
            ids.contains(_compareVersionId) &&
            _compareVersionId != version)
        ? _compareVersionId!
        : ids.firstWhere((id) => id != version,
            orElse: () => ids.isNotEmpty ? ids.first : '');

    return Material(
      key: const ValueKey('verse-bar'),
      color: cs.secondaryContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Space.lg, right: Space.xs),
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
                if (canSwitch) ...[
                  IconButton(
                    tooltip: 'Parallel comparison',
                    isSelected: _comparing,
                    icon: const Icon(AppIcons.compare),
                    selectedIcon:
                        Icon(AppIcons.compare, color: cs.onPrimary),
                    style: IconButton.styleFrom(
                      backgroundColor: _comparing ? cs.primary : null,
                    ),
                    onPressed: () => setState(() {
                      _comparing = !_comparing;
                      _compareVersionId = altId;
                    }),
                  ),
                  IconButton(
                    tooltip: 'Change translation',
                    icon: const Icon(AppIcons.translate),
                    onPressed: () => _pickVersion(run),
                  ),
                ],
                IconButton(
                  tooltip: run.link.open ? 'Collapse verse' : 'Expand verse',
                  icon: _swap(
                    Icon(
                      run.link.open
                          ? AppIcons.unfoldLess
                          : AppIcons.unfoldMore,
                      key: ValueKey(run.link.open),
                    ),
                  ),
                  onPressed: () => _rewrite(run, open: !run.link.open),
                ),
                IconButton(
                  tooltip: 'Remove verse styling (keep text)',
                  icon: const Icon(AppIcons.linkOff),
                  onPressed: () => _unlink(run),
                ),
              ],
            ),
          ),
          if (_comparing && canSwitch)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                  Space.lg, Space.sm, Space.lg, Space.md),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _ParallelPane(
                        versionId: version,
                        text: _verseText(
                            widget.bibles.version(version), ref, true),
                      ),
                    ),
                    VerticalDivider(width: Space.xl, color: cs.outlineVariant),
                    Expanded(
                      child: _ParallelPane(
                        versionId: altId,
                        text: _verseText(
                            widget.bibles.version(altId), ref, true),
                        availableIds:
                            ids.where((id) => id != version).toList(),
                        onChanged: (v) =>
                            setState(() => _compareVersionId = v),
                        onUseVersion: () => _rewrite(run, version: altId),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------- manual insertion & verse finder

  void _insertVerseRefAtCursor(VerseRef ref) {
    final maxIdx = _controller.document.length - 1;
    final sel = _controller.selection;
    var start = sel.isValid ? sel.start : maxIdx;
    if (start < 0 || start > maxIdx) start = maxIdx;
    var len = sel.isValid ? sel.end - sel.start : 0;
    if (start + len > maxIdx) len = maxIdx - start;

    final n = _writeVerse(
      ref,
      widget.settings.insertExpanded,
      start,
      len,
      (n) => start + n,
    );

    _controller.replaceText(
      start + n,
      0,
      ' ',
      TextSelection.collapsed(offset: start + n + 1),
    );
    _controller.formatText(start + n, 1, LinkAttribute(null));
    _focus.requestFocus();
  }

  Future<void> _promptInsertVerse() async {
    final bible = widget.bibles.version(null);
    if (bible == null) {
      _toast(kDebugMode
          ? 'No Bible loaded. Add XML files to assets/bibles/.'
          : 'No Bible is available.');
      return;
    }

    final picked = await showModalBottomSheet<VerseRef>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _VerseFinderSheet(bible: bible),
    );

    if (picked == null || !mounted) return;
    _insertVerseRefAtCursor(picked.withVersion(bible.id));
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------------------- UI

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    Color? color,
  }) =>
      PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: Space.md),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isNew = widget.note.title.isEmpty && widget.note.delta.isEmpty;

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
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: kMinHit),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.only(
                            left: Space.md, right: Space.xs),
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.bibles.selectedId ?? '',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const Icon(Icons.arrow_drop_down, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: widget.note.pinned ? 'Unpin' : 'Pin',
              icon: _swap(
                Icon(
                  widget.note.pinned ? AppIcons.pin : AppIcons.unpin,
                  key: ValueKey(widget.note.pinned),
                  color: widget.note.pinned ? cs.primary : null,
                ),
              ),
              onPressed: _togglePin,
            ),
            IconButton(
              tooltip: 'Insert or find verse',
              icon: const Icon(AppIcons.bible),
              onPressed: _promptInsertVerse,
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: _onMenu,
              itemBuilder: (_) => [
                _menuItem(
                    'export_md', AppIcons.exportMarkdown, 'Export Markdown (.md)'),
                _menuItem(
                    'export_pdf', AppIcons.exportPdf, 'Export PDF (.pdf)'),
                const PopupMenuDivider(),
                _menuItem(
                  'archive',
                  widget.note.archived ? AppIcons.unarchive : AppIcons.archive,
                  widget.note.archived ? 'Unarchive' : 'Archive',
                ),
                _menuItem('trash', AppIcons.trash, 'Delete', color: cs.error),
              ],
            ),
            const SizedBox(width: Space.xs),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: _maxEditorWidth),
                    child: Column(
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: Space.lg),
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
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: Space.sm),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: Space.lg),
                            child: MediaQuery(
                              data: media.copyWith(textScaler: scaler),
                              child: QuillEditor.basic(
                                controller: _controller,
                                focusNode: _focus,
                                scrollController: _scroll,
                                config: QuillEditorConfig(
                                  placeholder:
                                      'Start writing. Type a reference like “James 2:1” to insert the verse.',
                                  padding: const EdgeInsets.only(
                                      top: Space.sm, bottom: 80),
                                  customStyles: DefaultStyles(
                                    link: TextStyle(
                                      decoration: TextDecoration.underline,
                                      decorationStyle:
                                          TextDecorationStyle.dotted,
                                      decorationColor: cs.primary,
                                      decorationThickness: 1.5,
                                    ),
                                  ),
                                  onLaunchUrl: (_) {},
                                  embedBuilders: [VerseEmbedBuilder()],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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
                  config: QuillSimpleToolbarConfig(
                    multiRowsDisplay: false,
                    showFontFamily: false,
                    showSearchButton: false,
                    showSubscript: false,
                    showSuperscript: false,
                    showInlineCode: false,
                    showCodeBlock: false,
                    showSmallButton: false,
                    showLink: false,
                    showColorButton: false,
                    showBackgroundColorButton: false,
                    showListCheck: true,
                    customButtons: [
                      QuillToolbarCustomButtonOptions(
                        icon: const Icon(Icons.format_color_text, size: 20),
                        tooltip: 'Text color',
                        onPressed: () => _pickFormatColor(isBackground: false),
                      ),
                      QuillToolbarCustomButtonOptions(
                        icon: const Icon(Icons.format_color_fill, size: 20),
                        tooltip: 'Highlight color',
                        onPressed: () => _pickFormatColor(isBackground: true),
                      ),
                    ],
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

/// A colour choice in the picker. A null [color] is the "none/default" chip.
/// 48px target, labelled for screen readers, with a checkmark on the current
/// choice so selection isn't conveyed by colour alone.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fill = color ?? cs.surfaceContainerLowest;
    final onFill = ThemeData.estimateBrightnessForColor(fill) == Brightness.light
        ? Colors.black
        : Colors.white;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: kMinHit,
            height: kMinHit,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              border: Border.all(
                color: selected ? cs.primary : cs.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: selected
                ? Icon(AppIcons.check, size: 20, color: onFill)
                : (color == null
                    ? Icon(AppIcons.close,
                        size: 20, color: cs.onSurfaceVariant)
                    : null),
          ),
        ),
      ),
    );
  }
}

class _ParallelPane extends StatelessWidget {
  const _ParallelPane({
    required this.versionId,
    required this.text,
    this.availableIds,
    this.onChanged,
    this.onUseVersion,
  });

  final String versionId;
  final String text;
  final List<String>? availableIds;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onUseVersion;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (availableIds != null && availableIds!.length > 1)
              DropdownButton<String>(
                value: versionId,
                isDense: true,
                underline: const SizedBox.shrink(),
                style: tt.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
                items: [
                  for (final id in availableIds!)
                    DropdownMenuItem(value: id, child: Text(id)),
                ],
                onChanged: (v) {
                  if (v != null && onChanged != null) onChanged!(v);
                },
              )
            else
              Text(
                versionId,
                style: tt.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            const Spacer(),
            if (onUseVersion != null)
              TextButton(
                onPressed: onUseVersion,
                child: const Text('Use'),
              ),
          ],
        ),
        const SizedBox(height: Space.xs),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 112),
          child: SingleChildScrollView(
            child: Text(
              text,
              style: tt.bodyMedium?.copyWith(height: 1.4, color: cs.onSurface),
            ),
          ),
        ),
      ],
    );
  }
}

class _VerseFinderSheet extends StatefulWidget {
  const _VerseFinderSheet({required this.bible});

  final BibleVersion bible;

  @override
  State<_VerseFinderSheet> createState() => _VerseFinderSheetState();
}

class _VerseFinderSheetState extends State<_VerseFinderSheet> {
  final _ctl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submitInput() {
    final trimmed = _ctl.text.trim();
    if (trimmed.isEmpty) return;
    final parsed = parseReference(trimmed);
    if (parsed != null &&
        widget.bible.verse(parsed.book, parsed.chapter, parsed.verseStart) !=
            null) {
      Navigator.pop(context, parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final parsed = parseReference(_query.trim());
    final directText = parsed == null
        ? null
        : widget.bible.verse(parsed.book, parsed.chapter, parsed.verseStart);

    final hits = _query.trim().length < 2
        ? const <(VerseRef, String)>[]
        : widget.bible.search(_query);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Space.lg, Space.xs, Space.lg, Space.md),
                child: Text(
                  'Verse Finder (${widget.bible.id})',
                  style: tt.titleLarge,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: TextField(
                  controller: _ctl,
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  onSubmitted: (_) => _submitInput(),
                  decoration: const InputDecoration(
                    hintText:
                        'Type a reference (John 3:16) or keywords (faith works)…',
                    prefixIcon: Icon(AppIcons.search),
                  ),
                ),
              ),
              const SizedBox(height: Space.md),
              if (parsed != null && directText != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  child: Card(
                    color: cs.primaryContainer,
                    child: ListTile(
                      title: Text(
                        parsed.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      subtitle: Text(
                        directText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: cs.onPrimaryContainer),
                      ),
                      trailing: Icon(AppIcons.addCircle,
                          color: cs.onPrimaryContainer),
                      onTap: () => Navigator.pop(context, parsed),
                    ),
                  ),
                ),
              Flexible(
                child: hits.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(Space.xxl),
                        child: Center(
                          child: Text(
                            _query.trim().length < 2
                                ? 'Search any phrase or word when you can’t remember the exact reference.'
                                : 'No matching verses found.',
                            textAlign: TextAlign.center,
                            style: tt.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(
                            Space.lg, Space.xs, Space.lg, Space.lg),
                        itemCount: hits.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final (ref, verseText) = hits[i];
                          return ListTile(
                            title: Text(
                              ref.label,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              verseText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.pop(ctx, ref),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}