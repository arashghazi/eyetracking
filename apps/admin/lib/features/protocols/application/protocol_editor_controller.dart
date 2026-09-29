import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/protocols_repository.dart';

/// One stage row of the stage table, as text the researcher edits.
class StageDraft {
  StageDraft({
    required this.uid,
    this.faceLevel = 0,
    this.zone = NumberZone.outside,
    this.trials = '6',
    this.minCorrect = '0.8',
    this.mode = StageResponseMode.profile,
    this.trialSeconds = '8',
  });

  factory StageDraft.from(int uid, GradualStage s) => StageDraft(
        uid: uid,
        faceLevel: s.faceLevel,
        zone: s.numberZone,
        trials: '${s.trials}',
        minCorrect: _num(s.minCorrect),
        mode: s.responseMode,
        trialSeconds: _num(s.trialSeconds),
      );

  /// Stable identity for the widget of this row.
  final int uid;
  int faceLevel;
  NumberZone zone;
  String trials;
  String minCorrect;
  StageResponseMode mode;
  String trialSeconds;

  StageDraft copy(int uid) => StageDraft(
        uid: uid,
        faceLevel: faceLevel,
        zone: zone,
        trials: trials,
        minCorrect: minCorrect,
        mode: mode,
        trialSeconds: trialSeconds,
      );
}

String _num(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// Edits one protocol: a draft can be changed, saved and published; a
/// published version is read-only and only offers a new draft.
///
/// Numbers are kept as the text that was typed; a value that is not a number
/// is reported here, every other rule is checked by the server and its
/// message is shown exactly as it arrives.
class ProtocolEditorController extends SafeChangeNotifier {
  ProtocolEditorController(
    this._repository,
    this.studyId, {
    ProtocolDetail? initial,
    required this.canEdit,
  }) {
    if (initial == null) {
      _fill(null, const ProtocolDefinition(path: ProtocolPath.gradualFace));
      _stages
        ..clear()
        ..addAll([
          for (final s in ProtocolDefinition.starter(ProtocolPath.gradualFace)
              .gradual!
              .stages)
            StageDraft.from(_uid++, s),
        ]);
    } else {
      _fill(initial.summary, initial.definition);
    }
  }

  final ProtocolsRepository _repository;
  final int studyId;

  /// Researchers edit; analysts only look.
  final bool canEdit;

  int _uid = 0;

  String? _id;
  int _version = 0;
  String _status = ProtocolStatus.draft;

  String name = '';
  ProtocolPath path = ProtocolPath.gradualFace;
  String baselineSeconds = '30';
  String postSeconds = '30';

  int scaleMax = 5;
  List<String> labels = List.of(kDefaultComfortLabels);
  int minOk = 3;
  bool askEveryStage = true;

  String holdInvalid = '0.3';
  bool easierOnLowComfort = true;
  bool stopOnTwoLow = true;

  final List<StageDraft> _stages = [];
  NumberZone finalZoneLimit = NumberZone.nearEyes;
  bool allowSimultaneous = false;
  String realFaceUrl = '';

  String interactionPoints = '2';

  /// Bumped when the fields are replaced from the server, so the text boxes
  /// show the new values.
  int revision = 0;

  bool _busy = false;
  bool _dirty = false;
  String? _error;
  String? _notice;

  String? get id => _id;
  int get version => _version;
  String get status => _status;
  bool get isNew => _id == null;
  bool get isPublished => _status == ProtocolStatus.published;
  bool get readOnly => !canEdit || isPublished;
  bool get busy => _busy;
  bool get dirty => _dirty;
  String? get error => _error;
  String? get notice => _notice;
  List<StageDraft> get stages => List.unmodifiable(_stages);

  void _fill(ProtocolSummary? summary, ProtocolDefinition def) {
    _id = summary?.id;
    _version = summary?.version ?? 0;
    _status = summary?.status ?? ProtocolStatus.draft;
    name = summary?.name ?? '';
    path = def.path;
    baselineSeconds = _num(def.baselineSeconds);
    postSeconds = _num(def.postSeconds);
    scaleMax = def.comfort.scaleMax.clamp(3, 7);
    labels = List.of(def.comfort.labels);
    while (labels.length < scaleMax) {
      labels.add('');
    }
    if (labels.length > scaleMax) labels = labels.sublist(0, scaleMax);
    minOk = def.comfort.minOk.clamp(1, scaleMax);
    askEveryStage = def.comfort.askEveryStage;
    holdInvalid = _num(def.progression.holdOnInvalidShareAbove);
    easierOnLowComfort = def.progression.easierOnComfortBelowMin;
    stopOnTwoLow = def.progression.stopOnTwoLowComfort;
    _stages
      ..clear()
      ..addAll([
        for (final s in def.gradual?.stages ?? const <GradualStage>[])
          StageDraft.from(_uid++, s),
      ]);
    finalZoneLimit = def.gradual?.finalZoneLimit ?? NumberZone.nearEyes;
    allowSimultaneous = def.gradual?.allowSimultaneousChange ?? false;
    realFaceUrl = def.gradual?.realFaceMediaUrl ?? '';
    interactionPoints = '${def.interest?.interactionPoints ?? 2}';
    _dirty = false;
    revision++;
  }

  // ------------------------------------------------------------ editing

  /// Applies a change made in a field.
  void edit(void Function() change) {
    if (readOnly) return;
    change();
    _dirty = true;
    _error = null;
    _notice = null;
    notifyListeners();
  }

  void setPath(ProtocolPath value) => edit(() {
        path = value;
        if (value == ProtocolPath.gradualFace && _stages.isEmpty) {
          _stages.add(StageDraft(uid: _uid++));
        }
      });

  /// Changes the number of comfort values; labels are kept where they exist.
  void setScaleMax(int value) => edit(() {
        scaleMax = value;
        labels = [
          for (var i = 0; i < value; i++)
            i < labels.length
                ? labels[i]
                : (i < kDefaultComfortLabels.length ? kDefaultComfortLabels[i] : ''),
        ];
        if (minOk > value) minOk = value;
      });

  void setLabel(int index, String text) => edit(() => labels[index] = text);

  void addStage() => edit(() {
        _stages.add(_stages.isEmpty
            ? StageDraft(uid: _uid++)
            : _stages.last.copy(_uid++));
      });

  void removeStage(int uid) => edit(() => _stages.removeWhere((s) => s.uid == uid));

  // ------------------------------------------------------------ building

  double? _double(String label, String text) {
    final v = double.tryParse(text.trim().replaceAll(',', '.'));
    if (v == null || !v.isFinite) {
      _error = '$label must be a number.';
      return null;
    }
    return v;
  }

  int? _int(String label, String text) {
    final v = _double(label, text);
    if (v == null) return null;
    if (v != v.roundToDouble()) {
      _error = '$label must be a whole number.';
      return null;
    }
    return v.round();
  }

  /// The definition typed so far, or null (with [error] set) when a number
  /// cannot be read.
  ProtocolDefinition? _definition() {
    final baseline = _double('Baseline seconds', baselineSeconds);
    if (baseline == null) return null;
    final post = _double('Post seconds', postSeconds);
    if (post == null) return null;
    final hold = _double('Hold above invalid share', holdInvalid);
    if (hold == null) return null;

    GradualConfig? gradual;
    InterestConfig? interest;
    if (path == ProtocolPath.gradualFace) {
      final stages = <GradualStage>[];
      for (var i = 0; i < _stages.length; i++) {
        final s = _stages[i];
        final n = 'Stage ${i + 1}';
        final trials = _int('$n trials', s.trials);
        if (trials == null) return null;
        final minCorrect = _double('$n minimum correct', s.minCorrect);
        if (minCorrect == null) return null;
        final seconds = _double('$n seconds per number', s.trialSeconds);
        if (seconds == null) return null;
        stages.add(GradualStage(
          faceLevel: s.faceLevel,
          numberZone: s.zone,
          trials: trials,
          minCorrect: minCorrect,
          responseMode: s.mode,
          trialSeconds: seconds,
        ));
      }
      gradual = GradualConfig(
        stages: stages,
        finalZoneLimit: finalZoneLimit,
        allowSimultaneousChange: allowSimultaneous,
        realFaceMediaUrl: realFaceUrl.trim().isEmpty ? null : realFaceUrl.trim(),
      );
    } else {
      final points = _int('Interaction points', interactionPoints);
      if (points == null) return null;
      interest = InterestConfig(interactionPoints: points);
    }
    return ProtocolDefinition(
      path: path,
      baselineSeconds: baseline,
      postSeconds: post,
      comfort: ComfortConfig(
        scaleMax: scaleMax,
        labels: List.of(labels),
        minOk: minOk,
        askEveryStage: askEveryStage,
      ),
      progression: ProgressionRules(
        holdOnInvalidShareAbove: hold,
        easierOnComfortBelowMin: easierOnLowComfort,
        stopOnTwoLowComfort: stopOnTwoLow,
      ),
      gradual: gradual,
      interest: interest,
    );
  }

  // ------------------------------------------------------------ actions

  /// Saves the draft (creating it the first time). Returns true on success.
  Future<bool> save() async {
    if (readOnly || _busy) return false;
    _error = null;
    _notice = null;
    if (name.trim().isEmpty) {
      _error = 'Give the protocol a name.';
      notifyListeners();
      return false;
    }
    final def = _definition();
    if (def == null) {
      notifyListeners();
      return false;
    }
    _busy = true;
    notifyListeners();
    try {
      final saved = _id == null
          ? await _repository.create(studyId, name.trim(), def)
          : await _repository.update(studyId, _id!,
              name: name.trim(), definition: def);
      _fill(saved.summary, saved.definition);
      _notice = 'Draft saved.';
      return true;
    } catch (e) {
      // The server's own wording, exactly as it arrives.
      _error = userMessage(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Saves what was typed, then publishes it. A published version never
  /// changes again.
  Future<bool> publish() async {
    if (readOnly || _busy) return false;
    if (_id == null || _dirty) {
      if (!await save()) return false;
    }
    _busy = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      final published = await _repository.publish(studyId, _id!);
      _fill(published.summary, published.definition);
      _notice = 'Published as version ${published.summary.version}.';
      return true;
    } catch (e) {
      _error = userMessage(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Replaces this (published) protocol with a new draft copy.
  Future<bool> newDraft() async {
    if (!canEdit || _busy || _id == null) return false;
    _busy = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      final draft = await _repository.newDraft(studyId, _id!);
      _fill(draft.summary, draft.definition);
      _notice = 'A new draft was created from the published version.';
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
