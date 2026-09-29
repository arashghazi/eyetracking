import 'package:eyetracking_core/eyetracking_core.dart';

import '../../content/domain/content_repository.dart';
import '../../protocols/domain/protocols_repository.dart';
import '../domain/assignments_repository.dart';

/// Approved content that could be attached to an assignment.
class ContentChoice {
  const ContentChoice({required this.item, required this.matchesTopic});

  final ContentSummary item;

  /// One of the item's topic tags is the participant's topic.
  final bool matchesTopic;
}

/// The Assignments section of the participant detail: what is assigned, the
/// published protocols that can be assigned, and the approved content that
/// can be attached.
class ParticipantAssignmentsController extends SafeChangeNotifier {
  ParticipantAssignmentsController({
    required this.assignments,
    required this.protocols,
    required this.content,
    required this.studyId,
    required this.code,
  });

  final AssignmentsRepository assignments;
  final ProtocolsRepository protocols;
  final ContentRepository content;
  final int studyId;
  final String code;

  List<Assignment> _items = const [];
  List<ProtocolSummary> _published = const [];
  List<ContentSummary> _approved = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  bool _busy = false;
  String? _error;
  String? _notice;

  List<Assignment> get items => _items;
  List<ProtocolSummary> get publishedProtocols => _published;
  bool get loading => _loading;
  bool get loadedOnce => _loadedOnce;
  bool get busy => _busy;
  String? get error => _error;
  String? get notice => _notice;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await assignments.list(studyId, code);
      _loadedOnce = true;
    } catch (e) {
      _error = userMessage(e);
    }
    // Protocols and content only feed the pickers; the list works without.
    try {
      final all = await protocols.list(studyId);
      _published = [
        for (final p in all)
          if (p.isPublished) p,
      ];
    } catch (_) {
      _published = const [];
    }
    try {
      final all = await content.list(studyId);
      _approved = [
        for (final c in all)
          if (c.isApproved) c,
      ];
    } catch (_) {
      _approved = const [];
    }
    _loading = false;
    notifyListeners();
  }

  /// Approved content for [assignment]: items tagged with its topic first.
  List<ContentChoice> contentFor(Assignment assignment) {
    final topic = assignment.topic?.trim().toLowerCase() ?? '';
    bool matches(ContentSummary c) =>
        topic.isNotEmpty &&
        c.topicTags.any((t) => t.trim().toLowerCase() == topic);
    final choices = [
      for (final c in _approved)
        ContentChoice(item: c, matchesTopic: matches(c)),
    ];
    // Stable: matching items first, each group in the server's order.
    return [
      ...choices.where((c) => c.matchesTopic),
      ...choices.where((c) => !c.matchesTopic),
    ];
  }

  Future<bool> assign(String protocolId, {int? orderIndex}) => _act(() async {
        await assignments.create(
          studyId,
          code,
          protocolId: protocolId,
          orderIndex: orderIndex,
        );
        _notice = 'Protocol assigned.';
      });

  Future<bool> attach(String assignmentId, String contentId) => _act(() async {
        await assignments.attachContent(studyId, code, assignmentId, contentId);
        _notice = 'Content attached. The participant can start now.';
      });

  Future<bool> cancel(String assignmentId) => _act(() async {
        await assignments.cancel(studyId, code, assignmentId);
        _notice = 'Assignment cancelled.';
      });

  Future<bool> _act(Future<void> Function() action) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      await action();
      _items = await assignments.list(studyId, code);
      return true;
    } catch (e) {
      _error = userMessage(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }

  void dismissNotice() {
    _notice = null;
    notifyListeners();
  }
}
