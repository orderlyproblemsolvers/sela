import 'dart:convert';

import 'books.dart';

/// A reference such as James 2:1 or John 3:16-18, optionally pinned to the
/// Bible version it was inserted with.
class VerseRef {
  const VerseRef({
    required this.book,
    required this.chapter,
    required this.verseStart,
    required this.verseEnd,
    this.version,
  });

  final int book; // 1..66
  final int chapter;
  final int verseStart;
  final int verseEnd;
  final String? version;

  String get bookName => kBooks[book - 1].name;

  String get label {
    final r = verseEnd > verseStart ? '$verseStart-$verseEnd' : '$verseStart';
    return '$bookName $chapter:$r';
  }

  VerseRef withVersion(String? v) => VerseRef(
        book: book,
        chapter: chapter,
        verseStart: verseStart,
        verseEnd: verseEnd,
        version: v,
      );

  bool sameRef(VerseRef o) =>
      book == o.book &&
      chapter == o.chapter &&
      verseStart == o.verseStart &&
      verseEnd == o.verseEnd;

  Map<String, dynamic> toJson() => {
        'b': book,
        'c': chapter,
        'v1': verseStart,
        'v2': verseEnd,
        if (version != null) 'ver': version,
      };

  factory VerseRef.fromJson(Map<String, dynamic> j) => VerseRef(
        book: j['b'] as int,
        chapter: j['c'] as int,
        verseStart: j['v1'] as int,
        verseEnd: j['v2'] as int,
        version: j['ver'] as String?,
      );
}

/// Verse text in a note carries a Quill "link" attribute whose value is
/// `verse:<json>`. That is how we know a run of text is scripture.
const String kVerseLinkScheme = 'verse:';

class VerseLink {
  const VerseLink(this.ref, this.open);

  final VerseRef ref;

  /// true = full verse text shown, false = just the reference.
  final bool open;

  String get url => '$kVerseLinkScheme'
      '${Uri.encodeComponent(jsonEncode({...ref.toJson(), 'open': open}))}';

  static VerseLink? tryParse(String url) {
    if (!url.startsWith(kVerseLinkScheme)) return null;
    try {
      final m = jsonDecode(
              Uri.decodeComponent(url.substring(kVerseLinkScheme.length)))
          as Map<String, dynamic>;
      return VerseLink(VerseRef.fromJson(m), (m['open'] as bool?) ?? true);
    } catch (_) {
      return null;
    }
  }
}

/// Finds a reference at the END of [text]. Returns it with the index where
/// the reference starts inside [text], or null.
(VerseRef, int)? matchReferenceAtEnd(String text) {
  final m = kReferenceRegex.firstMatch(text);
  if (m == null) return null;
  final book = bookIndexFromName(m.group(1)!);
  final chapter = int.tryParse(m.group(2)!);
  final v1 = int.tryParse(m.group(3)!);
  if (book == null || chapter == null || v1 == null) return null;
  final v2 = m.group(4) == null ? v1 : (int.tryParse(m.group(4)!) ?? v1);
  if (v2 < v1) return null;
  return (
    VerseRef(book: book, chapter: chapter, verseStart: v1, verseEnd: v2),
    m.start,
  );
}

/// Parses a reference at the end of [text], or returns null.
VerseRef? parseReference(String text) => matchReferenceAtEnd(text)?.$1;
