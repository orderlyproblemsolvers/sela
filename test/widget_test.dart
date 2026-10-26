import 'package:flutter_test/flutter_test.dart';
import 'package:biblestudynotes/bible/verse_ref.dart';

void main() {
  test('parses a typed verse reference', () {
    final ref = parseReference('just like in james 2:1');
    expect(ref, isNotNull);
    expect(ref!.label, 'James 2:1');
  });

  test('parses ranges and numbered books', () {
    final ref = parseReference('see 1 john 3:16-18');
    expect(ref!.label, '1 John 3:16-18');
  });

  test('ignores things that are not references', () {
    expect(parseReference('meet at 9:30'), isNull);
  });
}