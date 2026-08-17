import 'dart:collection';

class ByteConsumer {
  final _queue = ListQueue<List<int>>();

  final _consumed = ListQueue<List<int>>();

  var _currentOffset = 0;

  var _length = 0;

  var _totalConsumed = 0;

  void add(String data) {
    if (data.isEmpty) return;
    final runes = data.runes.toList(growable: false);
    _queue.addLast(runes);
    _length += runes.length;
  }

  int peek() {
    final data = _queue.first;
    if (_currentOffset < data.length) {
      return data[_currentOffset];
    } else {
      final result = consume();
      rollback();
      return result;
    }
  }

  int consume() {
    final data = _queue.first;

    if (_currentOffset >= data.length) {
      _consumed.add(_queue.removeFirst());
      _currentOffset -= data.length;
      return consume();
    }

    _length--;
    _totalConsumed++;
    return data[_currentOffset++];
  }

  /// The block being consumed, so a caller can scan a run of bytes in one pass
  /// instead of paying [consume] per byte. Empty when nothing is pending.
  ///
  /// Retires finished blocks first: a block is only dropped when the next byte
  /// is asked for, so until then the offset can sit past its end.
  List<int> get pendingBlock {
    _retireFinishedBlocks();

    if (_queue.isEmpty) {
      return const <int>[];
    }

    return _queue.first;
  }

  /// Where in [pendingBlock] the next byte sits.
  int get pendingOffset => _currentOffset;

  /// Consumes [count] bytes the caller has already read from [pendingBlock].
  ///
  /// Bounded to that block on purpose — crossing into the next one is what
  /// [consume] is for, and rollback bookkeeping depends on blocks being retired
  /// in order.
  void skip(int count) {
    assert(count >= 0);
    assert(_queue.isNotEmpty);
    assert(_currentOffset + count <= _queue.first.length);

    _currentOffset += count;
    _length -= count;
    _totalConsumed += count;
  }

  void _retireFinishedBlocks() {
    while (_queue.isNotEmpty && _currentOffset >= _queue.first.length) {
      final finished = _queue.removeFirst();
      _consumed.add(finished);
      _currentOffset -= finished.length;
    }
  }

  /// Rolls back the last [n] call.
  void rollback([int n = 1]) {
    _currentOffset -= n;
    _totalConsumed -= n;
    _length += n;
    while (_currentOffset < 0) {
      final rollback = _consumed.removeLast();
      _queue.addFirst(rollback);
      _currentOffset += rollback.length;
    }
  }

  /// Rolls back to the state when this consumer had [length] bytes.
  void rollbackTo(int length) {
    rollback(length - _length);
  }

  int get length => _length;

  int get totalConsumed => _totalConsumed;

  bool get isEmpty => _length == 0;

  bool get isNotEmpty => _length != 0;

  /// Unreferences data blocks that have been consumed. After calling this
  /// method, the consumer will not be able to roll back to consumed blocks.
  void unrefConsumedBlocks() {
    _consumed.clear();
  }

  /// Resets the consumer to its initial state.
  void reset() {
    _queue.clear();
    _consumed.clear();
    _currentOffset = 0;
    _totalConsumed = 0;
    _length = 0;
  }
}

// void main() {
//   final consumer = ByteConsumer();
//   consumer.add(Uint8List.fromList([1, 2, 3]));
//   consumer.add(Uint8List.fromList([4, 5, 6]));

//   while (consumer.isNotEmpty) {
//     print(consumer.consume());
//   }

//   consumer.rollback(5);

//   while (consumer.isNotEmpty) {
//     print(consumer.consume());
//   }

//   consumer.rollbackTo(3);

//   while (consumer.isNotEmpty) {
//     print(consumer.consume());
//   }
// }
