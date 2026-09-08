import 'package:anime_now/util/batch_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('five lines survive a round trip through single mode', () {
    const full = 'a\nb\nc\nd\ne';
    final (visible, hidden) = BatchText.toSingle(full);
    expect(visible, 'a');
    expect(BatchText.hiddenCount(hidden), 4);
    expect(BatchText.keywords(visible, batch: false), ['a']);
    expect(BatchText.toBatch(visible, hidden), full);
  });

  test('editing the first line in single mode keeps the other lines', () {
    final (_, hidden) = BatchText.toSingle('a\nb\nc');
    expect(BatchText.toBatch('zzz', hidden), 'zzz\nb\nc');
  });

  test('single-mode text carries into batch mode as the first line', () {
    expect(BatchText.toBatch('hello', ''), 'hello');
    expect(BatchText.keywords('hello', batch: true), ['hello']);
  });

  test('batch keywords skip blank lines and trim', () {
    expect(BatchText.keywords(' a \n\n b\n', batch: true), ['a', 'b']);
  });
}
