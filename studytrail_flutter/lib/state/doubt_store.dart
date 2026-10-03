import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// The class doubt board: the list, and the doubt that's open.
class DoubtStore extends AsyncStore {
  DoubtStore({DoubtRepository? doubts, RoomRepository? moderation})
      : _doubts = doubts ?? const DoubtRepository(),
        _moderation = moderation ?? const RoomRepository();

  final DoubtRepository _doubts;

  /// Blocks are shared with study rooms (0013): one block hides a classmate
  /// everywhere.
  final RoomRepository _moderation;

  static const filters = {'all': 'All', 'open': 'Unsolved', 'mine': 'Mine'};

  String _filter = 'all';
  String get filter => _filter;

  List<DoubtSummary> _list = const [];
  List<DoubtSummary> get doubts => _list;

  DoubtThread? _thread;
  DoubtThread? get thread => _thread;

  /// True while the AI writes its answer (a few seconds).
  bool _askingAi = false;
  bool get askingAi => _askingAi;

  Future<void> load() => runLoad(() async {
        _list = await _doubts.getDoubts(filter: _filter);
      });

  Future<void> setFilter(String filter) async {
    if (filter == _filter) return;
    _filter = filter;
    notifyListeners();
    await load();
  }

  Future<bool> open(String id) async {
    _thread = _thread?.id == id ? _thread : null;
    notifyListeners();
    return _threadCall(() => _doubts.getDoubt(id));
  }

  /// Posts a doubt and opens it. Returns its id, or null with [error] set.
  Future<String?> post({
    required String title,
    String? body,
    String? subject,
  }) async {
    final ok = await _threadCall(
        () => _doubts.post(title: title, body: body, subject: subject));
    if (!ok) return null;
    await _refreshList();
    return _thread?.id;
  }

  Future<bool> answer(String body) {
    final t = _thread;
    if (t == null) return Future.value(false);
    return _threadCall(() => _doubts.answer(t.id, body), refreshList: true);
  }

  Future<bool> vote(String answerId) =>
      _threadCall(() => _doubts.vote(answerId));

  Future<bool> markSolved(String? answerId) {
    final t = _thread;
    if (t == null) return Future.value(false);
    return _threadCall(() => _doubts.markSolved(t.id, answerId),
        refreshList: true);
  }

  Future<bool> askAi() async {
    final t = _thread;
    if (t == null || _askingAi) return false;
    _askingAi = true;
    notifyListeners();
    try {
      return await _threadCall(() => _doubts.askAi(t.id), refreshList: true);
    } finally {
      _askingAi = false;
      notifyListeners();
    }
  }

  Future<bool> deleteAnswer(String answerId) async {
    final t = _thread;
    if (t == null) return false;
    final ok = await runMutation(() => _doubts.deleteAnswer(answerId));
    if (ok) await _threadCall(() => _doubts.getDoubt(t.id), refreshList: true);
    return ok;
  }

  Future<bool> deleteDoubt() async {
    final t = _thread;
    if (t == null) return false;
    final ok = await runMutation(() => _doubts.deleteDoubt(t.id));
    if (ok) {
      _thread = null;
      _list = _list.where((d) => d.id != t.id).toList();
      notifyListeners();
    }
    return ok;
  }

  Future<bool> report({
    required String reason,
    String? doubtId,
    String? answerId,
  }) =>
      runMutation(() =>
          _doubts.report(reason: reason, doubtId: doubtId, answerId: answerId));

  /// Hides [userId]'s doubts and answers here and their messages in rooms.
  Future<bool> block(String userId) async {
    final ok = await runMutation(() => _moderation.block(userId));
    if (ok) {
      final t = _thread;
      if (t != null) await _threadCall(() => _doubts.getDoubt(t.id));
      await _refreshList();
    }
    return ok;
  }

  Future<bool> _threadCall(Future<DoubtThread> Function() call,
      {bool refreshList = false}) async {
    DoubtThread? fresh;
    final ok = await runMutation(() async => fresh = await call());
    if (ok && fresh != null) {
      _thread = fresh;
      notifyListeners();
      if (refreshList) _refreshList().ignore();
    }
    return ok;
  }

  Future<void> _refreshList() async {
    try {
      _list = await _doubts.getDoubts(filter: _filter);
      notifyListeners();
    } catch (_) {
      // The open doubt is what the student is looking at; the list catches up
      // on the next load.
    }
  }
}
