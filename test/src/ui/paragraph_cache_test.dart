import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/paragraph_cache.dart';

/// A paragraph the cache lets go of is disposed at once. Its native memory is
/// far larger than its Dart object, so leaving it to a garbage collection keeps
/// that memory long after the cache stopped using it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const style = TextStyle(fontSize: 13);
  const textScaler = TextScaler.noScaling;

  test('the least recently used paragraph is disposed when the cache is full',
      () {
    final cache = ParagraphCache(2);

    final first = cache.performAndCacheLayout('a', style, textScaler, 1);
    final second = cache.performAndCacheLayout('b', style, textScaler, 2);

    cache.performAndCacheLayout('c', style, textScaler, 3);

    final firstAfterEviction = cache.getLayoutFromCache(1);

    expect(firstAfterEviction, isNull, reason: 'the full cache dropped "a"');
    expect(first.debugDisposed, isTrue);
    expect(second.debugDisposed, isFalse);
  });

  test('a hit keeps its paragraph, so the next drop takes the older one', () {
    final cache = ParagraphCache(2);

    final first = cache.performAndCacheLayout('a', style, textScaler, 1);
    final second = cache.performAndCacheLayout('b', style, textScaler, 2);

    cache.getLayoutFromCache(1);
    cache.performAndCacheLayout('c', style, textScaler, 3);

    expect(first.debugDisposed, isFalse);
    expect(second.debugDisposed, isTrue);
  });

  test('a paragraph stored again under its key disposes the one it replaces',
      () {
    final cache = ParagraphCache(2);

    final replaced = cache.performAndCacheLayout('a', style, textScaler, 1);
    final replacement = cache.performAndCacheLayout('a', style, textScaler, 1);

    final cached = cache.getLayoutFromCache(1);

    expect(cached, same(replacement));
    expect(replaced.debugDisposed, isTrue);
  });

  test('clear disposes every paragraph', () {
    final cache = ParagraphCache(4);

    final first = cache.performAndCacheLayout('a', style, textScaler, 1);
    final second = cache.performAndCacheLayout('b', style, textScaler, 2);

    cache.clear();

    expect(cache.length, 0);
    expect(first.debugDisposed, isTrue);
    expect(second.debugDisposed, isTrue);
  });
}
