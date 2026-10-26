import 'package:xml/xml.dart';

import 'books.dart';

/// Key used for every verse: book * 1,000,000 + chapter * 1,000 + verse.
int verseKey(int book, int chapter, int verse) =>
    book * 1000000 + chapter * 1000 + verse;

/// Parses a Bible XML file into {verseKey: text}.
///
/// Understands the common layouts:
///   Zefania : <BIBLEBOOK bnumber bname><CHAPTER cnumber><VERS vnumber>
///   OSIS    : <div type="book" osisID><chapter osisID><verse osisID>
///   Generic : <book name|number><chapter number><verse number>
///             (also the short <b n><c n><v n> form)
///
/// Must be a top-level function so it can run in an isolate via compute().
Map<int, String> parseBibleXml(String source) {
  var s = source;
  if (s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF) s = s.substring(1);
  final doc = XmlDocument.parse(s);
  final out = <int, String>{};
  _walk(doc.rootElement, null, null, _Counter(), out);
  return out;
}

class _Counter {
  int last = 0;
}

void _walk(
  XmlElement el,
  int? book,
  int? chapter,
  _Counter counter,
  Map<int, String> out,
) {
  final name = el.name.local.toLowerCase();

  if (_isBook(el, name)) {
    final idx = _bookIndex(el);
    for (final c in el.childElements) {
      _walk(c, idx, null, _Counter(), out);
    }
    return;
  }

  if (name == 'chapter' || name == 'c') {
    final ch = _chapterNumber(el) ?? chapter;
    final fresh = _Counter();
    for (final c in el.childElements) {
      _walk(c, book, ch, fresh, out);
    }
    return;
  }

  if (name == 'vers' || name == 'verse' || name == 'v') {
    _addVerse(el, book, chapter, counter, out);
    return;
  }

  for (final c in el.childElements) {
    _walk(c, book, chapter, counter, out);
  }
}

void _addVerse(
  XmlElement el,
  int? book,
  int? chapter,
  _Counter counter,
  Map<int, String> out,
) {
  final text = _verseText(el);
  if (text.isEmpty) return;

  var b = book;
  var c = chapter;
  var v = _verseNumber(el);

  // OSIS verses carry the full address: Gen.1.1
  final osis = _attr(el, ['osisid']);
  if (osis != null && (b == null || c == null || v == null)) {
    final parts = osis.split(RegExp(r'[\s-]')).first.split('.');
    if (parts.length >= 3) {
      b ??= bookIndexFromName(parts[0]);
      c ??= int.tryParse(parts[1]);
      v ??= int.tryParse(parts[2]);
    }
  }

  v ??= counter.last + 1;
  counter.last = v;

  if (b == null || c == null || b < 1 || b > 66) return;
  final key = verseKey(b, c, v);
  final existing = out[key];
  out[key] = existing == null ? text : '$existing $text';
}

bool _isBook(XmlElement el, String name) =>
    name == 'biblebook' ||
    name == 'book' ||
    name == 'b' ||
    (name == 'div' && _attr(el, ['type']) == 'book');

String? _attr(XmlElement e, List<String> keys) {
  for (final k in keys) {
    for (final a in e.attributes) {
      if (a.name.local.toLowerCase() == k) return a.value;
    }
  }
  return null;
}

int? _int(String? s) => s == null ? null : int.tryParse(s.trim());

int? _bookIndex(XmlElement e) {
  for (final k in const [
    'bname',
    'name',
    'osisid',
    'bsname',
    'shortname',
    'n',
    'id',
    'title',
  ]) {
    final v = _attr(e, [k]);
    if (v == null) continue;
    final i = bookIndexFromName(v);
    if (i != null) return i;
  }
  for (final k in const ['bnumber', 'number', 'num', 'n', 'id']) {
    final i = _int(_attr(e, [k]));
    if (i != null && i >= 1 && i <= 66) return i;
  }
  return null;
}

int? _chapterNumber(XmlElement e) {
  final direct = _int(_attr(e, ['cnumber', 'number', 'num', 'n']));
  if (direct != null) return direct;
  final osis = _attr(e, ['osisid']);
  if (osis != null) return _int(osis.split(' ').first.split('.').last);
  return null;
}

int? _verseNumber(XmlElement e) {
  final direct = _int(_attr(e, ['vnumber', 'number', 'num', 'n']));
  if (direct != null) return direct;
  final osis = _attr(e, ['osisid']);
  if (osis != null) {
    final first = osis.split(RegExp(r'[\s-]')).first;
    return _int(first.split('.').last);
  }
  return null;
}

String _verseText(XmlElement el) {
  final b = StringBuffer();
  void rec(XmlNode x) {
    if (x is XmlText || x is XmlCDATA) {
      b.write(x.value ?? '');
    } else if (x is XmlElement) {
      final n = x.name.local.toLowerCase();
      if (n == 'note' || n == 'rf') return; // footnotes
      for (final c in x.children) {
        rec(c);
      }
    }
  }

  rec(el);
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}
