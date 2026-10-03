import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Past papers screen: the student's uploaded papers, which units
/// they ask about most, and the mock exam built from that.
class ExamPapersStore extends AsyncStore {
  ExamPapersStore({ExamPaperRepository? papers, QuizRepository? quizzes})
      : _papers = papers ?? const ExamPaperRepository(),
        _quizzes = quizzes ?? const QuizRepository();

  final ExamPaperRepository _papers;
  final QuizRepository _quizzes;

  /// Plenty for five years of one subject's papers, both sittings.
  static const maxPapers = 12;

  List<ExamPaper> _list = const [];
  List<ExamPaper> get papers => _list;

  List<ExamTopic> _topics = const [];
  List<ExamTopic> get topics => _topics;

  bool get atLimit => _list.length >= maxPapers;
  bool get hasAnalyzed => _list.any((p) => p.analyzed);

  bool _makingMock = false;
  bool get makingMock => _makingMock;

  Future<void> load() => runLoad(() async {
        final results = await Future.wait([
          _papers.getPapers(),
          _papers.getTopics(),
        ]);
        _list = results[0] as List<ExamPaper>;
        _topics = results[1] as List<ExamTopic>;
      });

  /// Picks a PDF or photo of a paper, uploads it, and has it read. [year] is
  /// optional — the AI reads it off the paper when it's printed there.
  Future<bool> pickAndUpload({int? year}) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic'],
    );
    final file = result?.files.firstOrNull;
    if (file?.path == null) return false;
    return _addAndAnalyze(File(file!.path!), file.name, year);
  }

  Future<bool> snapAndUpload({int? year}) async {
    final XFile? shot;
    try {
      shot = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 2400,
        imageQuality: 85,
      );
    } catch (_) {
      setError("Couldn't open the camera.");
      return false;
    }
    if (shot == null) return false;
    final name = 'Paper ${year ?? DateTime.now().year} photo.jpg';
    return _addAndAnalyze(File(shot.path), name, year);
  }

  Future<bool> _addAndAnalyze(File file, String name, int? year) async {
    if (atLimit) {
      setError('You already have $maxPapers papers. Remove one first.');
      return false;
    }
    ExamPaper? paper;
    final stored = await runMutation(() async {
      paper = await _papers.upload(file: file, fileName: name, year: year);
      _list = [paper!.withStatus('analyzing'), ..._list];
    });
    if (!stored || paper == null) return false;
    return analyze(paper!);
  }

  /// Reads (or re-reads) one paper, then refreshes the list and the topics.
  Future<bool> analyze(ExamPaper paper) async {
    _list = [
      for (final p in _list) p.id == paper.id ? p.withStatus('analyzing') : p,
    ];
    notifyListeners();
    var ok = true;
    try {
      await _papers.analyze(paper.id);
    } catch (e) {
      ok = false;
      setError(e);
    }
    try {
      _list = await _papers.getPapers();
      _topics = await _papers.getTopics();
    } catch (_) {}
    notifyListeners();
    return ok;
  }

  Future<bool> remove(ExamPaper paper) => runMutation(() async {
        await _papers.delete(paper);
        _list = _list.where((p) => p.id != paper.id).toList();
        _topics = await _papers.getTopics();
      });

  Future<List<PaperQuestion>> questionsFor(ExamTopic topic) =>
      _papers.getQuestions(topic.unitLabel);

  /// Returns the new quiz's id, or null with [error] set.
  Future<String?> mockExam() async {
    String? quizId;
    _makingMock = true;
    final ok = await runMutation(() async {
      quizId = await _quizzes.generateMockExam();
    });
    _makingMock = false;
    notifyListeners();
    return ok ? quizId : null;
  }
}
