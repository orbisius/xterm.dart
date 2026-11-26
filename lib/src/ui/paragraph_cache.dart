import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:quiver/collection.dart';

/// A cache of laid out [Paragraph]s. This is used to avoid laying out the same
/// text multiple times, which is expensive.
///
/// A key is any value with equality: a single cell's paragraph is keyed by an
/// int, a run of text by a string that holds its whole style and text, so two
/// different runs can never share a key.
///
/// A paragraph the cache lets go of is disposed at once, so its native memory
/// is freed then rather than whenever a garbage collection runs, which cannot
/// see how large that memory is. A paragraph already painted is safe to
/// dispose: a frame keeps its own reference to the glyphs it drew.
class ParagraphCache {
  ParagraphCache(int maximumSize)
      : _cache = LruMap<Object, Paragraph>(maximumSize: maximumSize);

  final LruMap<Object, Paragraph> _cache;

  /// Returns a [Paragraph] for the given [key]. [key] is the same as the
  /// key argument to [performAndCacheLayout].
  Paragraph? getLayoutFromCache(Object key) {
    return _cache[key];
  }

  /// Applies [style] and [textScaler] to [text] and lays it out to create
  /// a [Paragraph]. The [Paragraph] is cached and can be retrieved with the
  /// same [key] by calling [getLayoutFromCache].
  Paragraph performAndCacheLayout(
    String text,
    TextStyle style,
    TextScaler textScaler,
    Object key,
  ) {
    final builder = ParagraphBuilder(style.getParagraphStyle());
    builder.pushStyle(style.getTextStyle(textScaler: textScaler));
    builder.addText(text);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: double.infinity));

    final replacedParagraph = _cache.remove(key);

    replacedParagraph?.dispose();

    // A full map drops its least recently used entry, the last of its keys,
    // without disposing it; that entry goes here instead. The walk to it runs
    // only when the cache is full, never on a hit.
    if (_cache.length >= _cache.maximumSize) {
      final oldestKey = _cache.keys.last;
      final oldestParagraph = _cache.remove(oldestKey);

      oldestParagraph?.dispose();
    }

    _cache[key] = paragraph;
    return paragraph;
  }

  /// Clears the cache. This should be called when the same text and style
  /// pair no longer produces the same layout. For example, when a font is
  /// loaded.
  void clear() {
    for (final paragraph in _cache.values) {
      paragraph.dispose();
    }

    _cache.clear();
  }

  /// Returns the number of [Paragraph]s in the cache.
  int get length {
    return _cache.length;
  }
}
