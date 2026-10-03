/// Where the student stands against their roadmap, from `get_roadmap_pace`.
///
/// "Expected" is a straight line from the roadmap's start to the exam, so
/// [behind] is how many topics short of that line they are today.
class RoadmapPace {
  const RoadmapPace({
    this.hasRoadmap = false,
    this.total = 0,
    this.done = 0,
    this.expected = 0,
    this.behind = 0,
    this.daysLeft = 0,
    this.perDay = 0,
    this.overdue = 0,
  });

  final bool hasRoadmap;
  final int total;
  final int done;
  final int expected;
  final int behind;
  final int daysLeft;

  /// Topics a day that finish the roadmap by the exam.
  final int perDay;

  /// Unfinished tasks scheduled on earlier days — they no longer show on Home.
  final int overdue;

  /// Worth offering a catch-up for.
  bool get needsCatchUp => hasRoadmap && (behind > 0 || overdue > 0);

  factory RoadmapPace.fromMap(Map<String, dynamic> m) {
    int n(String key) => (m[key] as num?)?.toInt() ?? 0;
    return RoadmapPace(
      hasRoadmap: m['has_roadmap'] == true,
      total: n('total'),
      done: n('done'),
      expected: n('expected'),
      behind: n('behind'),
      daysLeft: n('days_left'),
      perDay: n('per_day'),
      overdue: n('overdue'),
    );
  }
}

/// What `plan_catch_up` did.
class CatchUpResult {
  const CatchUpResult({
    this.perDay = 0,
    this.moved = 0,
    this.scheduled = 0,
    this.daysLeft = 0,
  });

  final int perDay;

  /// Missed tasks brought forward to today.
  final int moved;

  /// Roadmap tasks newly placed on the coming days.
  final int scheduled;
  final int daysLeft;

  factory CatchUpResult.fromMap(Map<String, dynamic> m) {
    int n(String key) => (m[key] as num?)?.toInt() ?? 0;
    return CatchUpResult(
      perDay: n('per_day'),
      moved: n('moved'),
      scheduled: n('scheduled'),
      daysLeft: n('days_left'),
    );
  }
}
