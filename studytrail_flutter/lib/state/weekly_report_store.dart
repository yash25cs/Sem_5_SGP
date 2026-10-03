import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the weekly report screen.
class WeeklyReportStore extends AsyncStore {
  WeeklyReportStore({GamificationRepository? game})
      : _game = game ?? const GamificationRepository();

  final GamificationRepository _game;

  WeeklyReport? _report;
  WeeklyReport? get report => _report;

  Future<void> load() => runLoad(() async {
        _report = await _game.getWeeklyReport();
      });
}
