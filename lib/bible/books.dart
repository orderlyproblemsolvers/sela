// The 66 books, every spelling we recognise, and the regex that finds
// references like "James 2:1", "1 Jn 3:16-18" or "Song of Solomon 2:4".

class BookInfo {
  const BookInfo(this.index, this.name, this.forms);

  /// 1..66 (Genesis = 1, Revelation = 66)
  final int index;
  final String name;

  /// Lower-case typed forms, single spaces.
  final List<String> forms;
}

// (base name, leading number or 0, abbreviations)
const List<(String, int, List<String>)> _defs = [
  ('Genesis', 0, ['gen', 'ge', 'gn']),
  ('Exodus', 0, ['exod', 'exo', 'ex']),
  ('Leviticus', 0, ['lev', 'lv']),
  ('Numbers', 0, ['num', 'nm', 'nb']),
  ('Deuteronomy', 0, ['deut', 'deu', 'dt']),
  ('Joshua', 0, ['josh', 'jos', 'jsh']),
  ('Judges', 0, ['judg', 'jdg', 'jg']),
  ('Ruth', 0, ['rut']),
  ('Samuel', 1, ['sam', 'sa', 'sm']),
  ('Samuel', 2, ['sam', 'sa', 'sm']),
  ('Kings', 1, ['kgs', 'ki', 'kin']),
  ('Kings', 2, ['kgs', 'ki', 'kin']),
  ('Chronicles', 1, ['chron', 'chr', 'ch']),
  ('Chronicles', 2, ['chron', 'chr', 'ch']),
  ('Ezra', 0, ['ezr']),
  ('Nehemiah', 0, ['neh']),
  ('Esther', 0, ['esth', 'est']),
  ('Job', 0, []),
  ('Psalms', 0, ['psalm', 'ps', 'psa', 'pslm']),
  ('Proverbs', 0, ['prov', 'pro', 'prv']),
  ('Ecclesiastes', 0, ['eccles', 'eccl', 'ecc']),
  ('Song of Solomon', 0, ['song of songs', 'song', 'sos', 'canticles']),
  ('Isaiah', 0, ['isa']),
  ('Jeremiah', 0, ['jer']),
  ('Lamentations', 0, ['lam']),
  ('Ezekiel', 0, ['ezek', 'eze']),
  ('Daniel', 0, ['dan']),
  ('Hosea', 0, ['hos']),
  ('Joel', 0, []),
  ('Amos', 0, []),
  ('Obadiah', 0, ['obad', 'oba']),
  ('Jonah', 0, ['jon']),
  ('Micah', 0, ['mic']),
  ('Nahum', 0, ['nah']),
  ('Habakkuk', 0, ['hab']),
  ('Zephaniah', 0, ['zeph', 'zep']),
  ('Haggai', 0, ['hag']),
  ('Zechariah', 0, ['zech', 'zec']),
  ('Malachi', 0, ['mal']),
  ('Matthew', 0, ['matt', 'mat', 'mt']),
  ('Mark', 0, ['mrk', 'mk']),
  ('Luke', 0, ['luk', 'lk']),
  ('John', 0, ['joh', 'jhn', 'jn']),
  ('Acts', 0, ['act']),
  ('Romans', 0, ['rom', 'rm']),
  ('Corinthians', 1, ['cor', 'co']),
  ('Corinthians', 2, ['cor', 'co']),
  ('Galatians', 0, ['gal']),
  ('Ephesians', 0, ['eph']),
  ('Philippians', 0, ['phil', 'php']),
  ('Colossians', 0, ['col']),
  ('Thessalonians', 1, ['thess', 'thes', 'th']),
  ('Thessalonians', 2, ['thess', 'thes', 'th']),
  ('Timothy', 1, ['tim', 'ti']),
  ('Timothy', 2, ['tim', 'ti']),
  ('Titus', 0, ['tit']),
  ('Philemon', 0, ['philem', 'phlm', 'phm']),
  ('Hebrews', 0, ['heb']),
  ('James', 0, ['jas', 'jam', 'jm']),
  ('Peter', 1, ['pet', 'pe', 'pt']),
  ('Peter', 2, ['pet', 'pe', 'pt']),
  ('John', 1, ['joh', 'jhn', 'jn']),
  ('John', 2, ['joh', 'jhn', 'jn']),
  ('John', 3, ['joh', 'jhn', 'jn']),
  ('Jude', 0, ['jud']),
  ('Revelation', 0, ['rev', 'rv', 'revelations']),
];

const Map<int, List<String>> _prefixes = {
  1: ['1', '1st', 'first'],
  2: ['2', '2nd', 'second'],
  3: ['3', '3rd', 'third'],
};

const List<String> _romans = ['i', 'ii', 'iii'];

final List<BookInfo> kBooks = _buildBooks();
final Map<String, int> _lookup = _buildLookup();

/// Matches a reference at the END of a string. Groups:
/// 1 = book text, 2 = chapter, 3 = first verse, 4 = last verse (optional).
final RegExp kReferenceRegex = _buildRegex();

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// "1 John", "1john", "I John", "Gen", "Genesis" -> book index, or null.
int? bookIndexFromName(String name) => _lookup[_norm(name)];

List<BookInfo> _buildBooks() {
  final out = <BookInfo>[];
  for (var i = 0; i < _defs.length; i++) {
    final (base, n, abbrs) = _defs[i];
    final bases = <String>[base.toLowerCase(), ...abbrs];
    final forms = <String>[];
    for (final b in bases) {
      if (n == 0) {
        forms.add(b);
      } else {
        for (final p in _prefixes[n]!) {
          forms.add('$p $b');
        }
      }
    }
    out.add(BookInfo(i + 1, n == 0 ? base : '$n $base', forms));
  }
  return out;
}

Map<String, int> _buildLookup() {
  final m = <String, int>{};
  for (final b in kBooks) {
    m.putIfAbsent(_norm(b.name), () => b.index);
  }
  for (final b in kBooks) {
    for (final f in b.forms) {
      m.putIfAbsent(_norm(f), () => b.index);
    }
  }
  // Roman numerals, full names only ("II Samuel"); abbreviations would
  // clash with real books (e.g. "isa" is Isaiah, not "I Sa").
  for (var i = 0; i < _defs.length; i++) {
    final (base, n, _) = _defs[i];
    if (n > 0) {
      m.putIfAbsent('${_romans[n - 1]}${_norm(base)}', () => i + 1);
    }
  }
  return m;
}

RegExp _buildRegex() {
  final forms = <String>{};
  for (final b in kBooks) {
    forms.addAll(b.forms);
  }
  final sorted = forms.toList()..sort((a, b) => b.length.compareTo(a.length));
  final alt = sorted
      .map((f) => RegExp.escape(f).replaceAll(' ', r'\s*'))
      .join('|');
  return RegExp(
    r'(?<![A-Za-z0-9])(' +
        alt +
        r')\.?\s*(\d{1,3})\s*:\s*(\d{1,3})(?:\s*[-\u2013\u2014]\s*(\d{1,3}))?$',
    caseSensitive: false,
  );
}
