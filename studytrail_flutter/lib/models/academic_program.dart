/// The programs the academic-details form offers, grouped the way students
/// look for them, and the `profiles.branch` text a choice is saved as.
///
/// `branch` stays one text column — "B.Tech / B.E. · Computer Engineering ·
/// Semester 5", or "School · Class 10" — so nothing on the server changed, and
/// a profile saved before the dropdown (typed text) still opens:
/// [AcademicPlace.parse] reads an unknown program as "Other" with that text.
library;

class AcademicProgram {
  const AcademicProgram(this.name,
      {this.terms = 8, this.termLabel = 'Semester', this.levels});

  final String name;

  /// How many numbered terms: "Semester 1" … "Semester [terms]".
  final int terms;

  /// "Semester", "Class" or "Level" — what the form calls [options].
  final String termLabel;

  /// Named stages instead of numbered terms, for CA, CS and CMA.
  final List<String>? levels;

  /// What the term dropdown lists for this program.
  List<String> get options =>
      levels ?? [for (var i = 1; i <= terms; i++) '$termLabel $i'];

  bool get isSchool => name == school.name;
  bool get isOther => name == other.name;

  /// A school student picks a class instead of a semester, and has no
  /// branch.
  static const school =
      AcademicProgram('School', terms: 12, termLabel: 'Class');

  /// Anything not listed: the student types the program's name.
  static const other = AcademicProgram('Other', terms: 10);

  static const _caLevels = ['Foundation', 'Intermediate', 'Final'];

  /// Every program, under the heading the dropdown shows it in.
  static const groups = <(String, List<AcademicProgram>)>[
    ('School', [school]),
    (
      'Science & Technology',
      [
        AcademicProgram('B.Tech / B.E.'),
        AcademicProgram('B.Sc'),
        AcademicProgram('BCA'),
        AcademicProgram('Diploma Engineering', terms: 6),
        AcademicProgram('B.Pharm'),
        AcademicProgram('MBBS', terms: 10),
        AcademicProgram('BDS', terms: 10),
        AcademicProgram('B.Sc Nursing'),
        AcademicProgram('BPT (Physiotherapy)'),
        AcademicProgram('B.Arch', terms: 10),
        AcademicProgram('M.Tech / M.E.', terms: 4),
        AcademicProgram('M.Sc', terms: 4),
        AcademicProgram('MCA', terms: 4),
        AcademicProgram('M.Pharm', terms: 4),
      ]
    ),
    (
      'Commerce & Management',
      [
        AcademicProgram('B.Com'),
        AcademicProgram('BBA'),
        AcademicProgram('BMS'),
        AcademicProgram('BHM (Hotel Management)'),
        AcademicProgram('M.Com', terms: 4),
        AcademicProgram('MBA', terms: 4),
        AcademicProgram('PGDM', terms: 4),
        AcademicProgram('CA (Chartered Accountancy)',
            termLabel: 'Level', levels: _caLevels),
        AcademicProgram('CS (Company Secretary)',
            termLabel: 'Level', levels: ['CSEET', 'Executive', 'Professional']),
        AcademicProgram('CMA (Cost Accountancy)',
            termLabel: 'Level', levels: _caLevels),
      ]
    ),
    (
      'Arts & Humanities',
      [
        AcademicProgram('B.A.'),
        AcademicProgram('BFA (Fine Arts)'),
        AcademicProgram('B.Des (Design)'),
        AcademicProgram('BJMC (Journalism)', terms: 6),
        AcademicProgram('BSW (Social Work)', terms: 6),
        AcademicProgram('LLB', terms: 6),
        AcademicProgram('BA LLB', terms: 10),
        AcademicProgram('B.Ed', terms: 4),
        AcademicProgram('M.A.', terms: 4),
        AcademicProgram('MFA', terms: 4),
        AcademicProgram('MSW', terms: 4),
        AcademicProgram('M.Ed', terms: 4),
        AcademicProgram('LLM', terms: 4),
      ]
    ),
    ('Other', [other]),
  ];

  static AcademicProgram? byName(String name) {
    for (final (_, programs) in groups) {
      for (final program in programs) {
        if (program.name == name) return program;
      }
    }
    return null;
  }
}

/// What the academic form holds: a program, and the parts that go with it.
class AcademicPlace {
  const AcademicPlace({
    required this.program,
    this.customProgram = '',
    this.specialisation = '',
    this.term,
  });

  final AcademicProgram program;

  /// The typed program name, when [program] is "Other".
  final String customProgram;

  /// Branch or major. Never saved for school.
  final String specialisation;

  /// One of [AcademicProgram.options].
  final String? term;

  /// The `profiles.branch` text. "·" separates the parts, so one typed by
  /// the student becomes "-" rather than splitting a part in two on [parse].
  String format() => [
        program.isOther ? _clean(customProgram) : program.name,
        if (!program.isSchool) _clean(specialisation),
        term ?? '',
      ].where((s) => s.isNotEmpty).join(' · ');

  /// Reads [format]'s text back. Null for an empty or missing value.
  static AcademicPlace? parse(String? stored) {
    final parts = (stored ?? '')
        .split('·')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;

    final known = AcademicProgram.byName(parts.first);
    final program = known ?? AcademicProgram.other;
    final rest = parts.sublist(1);
    final term = rest.isNotEmpty && program.options.contains(rest.last)
        ? rest.removeLast()
        : null;
    return AcademicPlace(
      program: program,
      customProgram: known == null ? parts.first : '',
      specialisation: program.isSchool ? '' : rest.join(' · '),
      term: term,
    );
  }

  static String _clean(String s) => s.replaceAll('·', '-').trim();
}
