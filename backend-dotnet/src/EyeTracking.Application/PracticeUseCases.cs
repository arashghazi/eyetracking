using System.Text.Json.Nodes;
using EyeTracking.Domain;
using static EyeTracking.Application.Authz;
using static EyeTracking.Domain.PracticeRules;

namespace EyeTracking.Application;

/// <summary>One trial as the participant app sends it (the TrialIn request model, with its defaults).</summary>
public sealed record TrialInput(int StageIndex, int TMs, string NumberShown, string Zone, int FaceLevel)
{
    public int TrialIndex { get; init; }
    public JsonObject Position { get; init; } = [];
    public string? Response { get; init; }
    public int? ResponseMs { get; init; }
}

/// <summary>Content fields a researcher may change; null means "not sent" (left as it is).</summary>
public sealed record ContentChanges(
    string? Title = null,
    JsonObject? Definition = null,
    IReadOnlyList<string>? TopicTags = null,
    string? FaceId = null,
    string? VoiceId = null);

/// <summary>Use cases for build step 3 (practice_use_cases.py): protocols, content and private
/// media, assignments and the two practice paths. The session hooks at the end are called from
/// the measurement use cases; summaries and details are free-form JSON like the Python dicts.</summary>
public static class PracticeUseCases
{
    public const int MaxTrialBatch = 200;

    private static JsonNode? Ts(DateTime? t) => t is null ? null : JsonFormat.Timestamp(t.Value);

    private static JsonNode? F(double? v) => v is null ? null : Json.Float(v.Value);

    /// <summary>Python's <c>text[:n]</c> (code points, not UTF-16 units).</summary>
    private static string Head(string text, int n) =>
        string.Concat(text.EnumerateRunes().Take(n).Select(r => r.ToString()));

    /// <summary>Free text cut to its SQL Server column. SQLite kept any length, so Python stored the
    /// whole value; here a longer value is cut to fit instead of failing the request.</summary>
    private static string Fit(string text, int max)
    {
        if (text.Length <= max)
            return text;
        var cut = text[..max];
        return char.IsHighSurrogate(cut[^1]) ? cut[..^1] : cut;
    }

    private static List<string> Tags(IEnumerable<string> tags) =>
        tags.Where(t => t.Trim().Length > 0).Select(t => t.Trim().ToLowerInvariant()).ToList();

    private static JsonArray Stages(JsonObject definition) => (JsonArray)AsDict(definition["gradual"])["stages"]!;

    // ---------- protocols ----------

    private static Protocol ProtocolInStudy(IUnitOfWork uow, int studyId, int protocolId)
    {
        var p = uow.Protocols.Get(protocolId);
        if (p is null || p.StudyId != studyId)
            throw new NotFound("protocol not found");
        return p;
    }

    public static List<Protocol> ListProtocols(IUnitOfWork uow, Principal principal, int studyId)
    {
        RequireStudyAccess(principal, studyId);
        return uow.Protocols.ListForStudy(studyId);
    }

    public static Protocol GetProtocol(IUnitOfWork uow, Principal principal, int studyId, int protocolId)
    {
        RequireStudyAccess(principal, studyId);
        return ProtocolInStudy(uow, studyId, protocolId);
    }

    public static Protocol CreateProtocol(IUnitOfWork uow, Principal principal, int studyId, string? name, JsonObject definition)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        if (uow.Studies.Get(studyId) is null)
            throw new NotFound("study not found");
        if (string.IsNullOrWhiteSpace(name))
            throw new Invalid("name is required");
        ValidateProtocol(definition);
        var p = uow.Protocols.Add(new Protocol { StudyId = studyId, Name = Fit(name.Trim(), 200), Definition = definition });
        uow.Commit();
        return p;
    }

    public static Protocol UpdateProtocol(IUnitOfWork uow, Principal principal, int studyId, int protocolId, string? name, JsonObject? definition)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        var p = ProtocolInStudy(uow, studyId, protocolId);
        p.EnsureDraft();
        if (name is not null)
        {
            if (name.Trim().Length == 0)
                throw new Invalid("name is required");
            p.Name = Fit(name.Trim(), 200);
        }
        if (definition is not null)
        {
            ValidateProtocol(definition);
            p.Definition = definition;
        }
        uow.Commit();
        return p;
    }

    public static Protocol PublishProtocol(IUnitOfWork uow, IClock clock, Principal principal, int studyId, int protocolId)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        var p = ProtocolInStudy(uow, studyId, protocolId);
        p.EnsureDraft();
        ValidateProtocol(p.Definition);
        p.Status = ProtocolStatus.Published;
        p.Version = uow.Protocols.MaxVersion(studyId) + 1;
        p.PublishedAt = clock.Now();
        uow.Commit();
        return p;
    }

    public static Protocol NewDraftFrom(IUnitOfWork uow, Principal principal, int studyId, int protocolId)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        var src = ProtocolInStudy(uow, studyId, protocolId);
        var p = uow.Protocols.Add(new Protocol { StudyId = studyId, Name = src.Name, Definition = Json.CloneObj(src.Definition) });
        uow.Commit();
        return p;
    }

    // ---------- content ----------

    private static ContentItem ContentInStudy(IUnitOfWork uow, int studyId, int contentId)
    {
        var c = uow.Content.Get(contentId);
        if (c is null || c.StudyId != studyId)
            throw new NotFound("content not found");
        return c;
    }

    /// <summary>Media keys the segments name that have no uploaded file, sorted.</summary>
    public static List<string> MissingMedia(IUnitOfWork uow, ContentItem c)
    {
        var present = uow.Media.ListForContent(c.Id).Select(m => m.Key).ToHashSet(StringComparer.Ordinal);
        return c.MediaKeys().Where(k => !present.Contains(k)).Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToList();
    }

    public static List<(ContentItem Item, List<string> Missing)> ListContent(IUnitOfWork uow, Principal principal, int studyId)
    {
        RequireStudyAccess(principal, studyId);
        return uow.Content.ListForStudy(studyId).Select(c => (c, MissingMedia(uow, c))).ToList();
    }

    public static (ContentItem Item, List<string> Missing) GetContent(IUnitOfWork uow, Principal principal, int studyId, int contentId)
    {
        RequireStudyAccess(principal, studyId);
        var c = ContentInStudy(uow, studyId, contentId);
        return (c, MissingMedia(uow, c));
    }

    public static ContentItem CreateContent(
        IUnitOfWork uow, IClock clock, Principal principal, int studyId, string? title, JsonObject definition, IReadOnlyList<string> topicTags, string? faceId, string? voiceId)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        if (uow.Studies.Get(studyId) is null)
            throw new NotFound("study not found");
        if (string.IsNullOrWhiteSpace(title))
            throw new Invalid("title is required");
        ValidateContent(definition);
        var c = new ContentItem
        {
            StudyId = studyId, Title = Fit(title.Trim(), 200), Definition = definition, TopicTags = Tags(topicTags),
            FaceId = Fit(faceId ?? "", 100), VoiceId = Fit(voiceId ?? "", 100), CreatedAt = clock.Now(), UpdatedAt = clock.Now(),
        };
        c = uow.Content.Add(c);
        uow.Commit();
        return c;
    }

    public static ContentItem UpdateContent(IUnitOfWork uow, IClock clock, Principal principal, int studyId, int contentId, ContentChanges changes)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        var c = ContentInStudy(uow, studyId, contentId);
        c.EnsureDraft();
        if (changes.Definition is not null)
        {
            ValidateContent(changes.Definition);
            c.Definition = changes.Definition;
            c.TextReviewed = false;
        }
        if (changes.Title is not null)
            c.Title = changes.Title.Trim() is { Length: > 0 } title ? Fit(title, 200) : c.Title;
        if (changes.TopicTags is not null)
            c.TopicTags = Tags(changes.TopicTags);
        if (changes.FaceId is not null)
            c.FaceId = Fit(changes.FaceId, 100);
        if (changes.VoiceId is not null)
            c.VoiceId = Fit(changes.VoiceId, 100);
        c.UpdatedAt = clock.Now();
        uow.Commit();
        return c;
    }

    public static ContentItem ApproveContent(IUnitOfWork uow, IClock clock, Principal principal, int studyId, int contentId)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        var c = ContentInStudy(uow, studyId, contentId);
        c.EnsureDraft();
        ValidateContent(c.Definition);
        var missing = MissingMedia(uow, c);
        if (missing.Count > 0)
            throw new Invalid("missing media: " + string.Join(", ", missing));
        c.Status = ContentStatus.Approved;
        c.UpdatedAt = clock.Now();
        uow.Commit();
        return c;
    }

    public static ContentMedia UploadMedia(
        IUnitOfWork uow, IMediaStore store, Principal principal, int studyId, int contentId, string key, string contentType, byte[] data)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        ContentInStudy(uow, studyId, contentId).EnsureDraft();
        key = SafeKey(key);
        if (!MediaTypes.Contains(contentType))
            throw new Invalid($"content type must be one of [{string.Join(", ", MediaTypes.Order(StringComparer.Ordinal).Select(t => $"'{t}'"))}]");
        if (data.Length == 0)
            throw new Invalid("empty file");
        if (data.Length > MaxMediaBytes)
            throw new Invalid("file is larger than 200 MB");
        var rel = store.Save($"study-{studyId}/content-{contentId}/{key}", data);
        var media = uow.Media.ByKey(contentId, key);
        if (media is not null)
        {
            media.Path = rel;
            media.ContentType = contentType;
            media.Size = data.Length;
        }
        else
        {
            media = uow.Media.Add(new ContentMedia { ContentId = contentId, Key = key, Path = rel, ContentType = contentType, Size = data.Length });
        }
        uow.Commit();
        return media;
    }

    public static JsonArray ListMedia(IUnitOfWork uow, IMediaSigner signer, Principal principal, int studyId, int contentId)
    {
        RequireStudyAccess(principal, studyId);
        var c = ContentInStudy(uow, studyId, contentId);
        return new JsonArray(uow.Media.ListForContent(c.Id).Select(m => (JsonNode?)new JsonObject
        {
            ["key"] = m.Key, ["content_type"] = m.ContentType, ["size"] = m.Size, ["url"] = $"/media/{signer.Sign(m.Id)}",
        }).ToArray());
    }

    public static ContentMedia ResolveMedia(IUnitOfWork uow, IMediaSigner signer, string token)
    {
        var mediaId = signer.Verify(token);
        var m = mediaId is { } id ? uow.Media.Get(id) : null;
        return m ?? throw new NotFound("media link is invalid or has expired");
    }

    // ---------- assignments ----------

    private static Participant ParticipantInStudy(IUnitOfWork uow, int studyId, string code) =>
        uow.Participants.ByCode(studyId, code) ?? throw new NotFound("participant not found");

    private static JsonObject AssignmentView(IUnitOfWork uow, Assignment a)
    {
        var proto = uow.Protocols.Get(a.ProtocolId);
        var content = a.ContentId is { } cid && cid != 0 ? uow.Content.Get(cid) : null;
        return new JsonObject
        {
            ["id"] = a.Id,
            ["order_index"] = a.OrderIndex,
            ["status"] = a.Status.Value(),
            ["protocol"] = proto is null
                ? null
                : new JsonObject { ["id"] = proto.Id, ["name"] = proto.Name, ["version"] = proto.Version, ["path"] = proto.Path },
            ["topic"] = a.Topic,
            ["topic_free_text"] = a.TopicFreeText,
            ["content_id"] = a.ContentId,
            ["content_title"] = content?.Title,
            ["created_at"] = Ts(a.CreatedAt),
        };
    }

    private static JsonArray Views(IUnitOfWork uow, IEnumerable<Assignment> assignments) =>
        new(assignments.Select(a => (JsonNode?)AssignmentView(uow, a)).ToArray());

    public static JsonArray ListAssignments(IUnitOfWork uow, Principal principal, int studyId, string code)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher, StudyRole.Analyst);
        var p = ParticipantInStudy(uow, studyId, code);
        return Views(uow, uow.Assignments.ListForParticipant(p.Id));
    }

    public static JsonObject CreateAssignment(IUnitOfWork uow, Principal principal, int studyId, string code, int protocolId, int? orderIndex)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        var p = ParticipantInStudy(uow, studyId, code);
        var proto = ProtocolInStudy(uow, studyId, protocolId);
        if (proto.Status != ProtocolStatus.Published)
            throw new Invalid("only published protocol versions can be assigned");
        var existing = uow.Assignments.ListForParticipant(p.Id);
        var status = proto.Path is "interest_conversation" or "live_conversation" ? AssignmentStatus.PendingTopic : AssignmentStatus.Ready;
        var a = uow.Assignments.Add(new Assignment
        {
            ParticipantId = p.Id, StudyId = studyId, ProtocolId = proto.Id, OrderIndex = orderIndex ?? existing.Count, Status = status,
        });
        uow.Commit();
        return AssignmentView(uow, a);
    }

    public static JsonObject UpdateAssignment(IUnitOfWork uow, Principal principal, int studyId, string code, int assignmentId, int? contentId, string? status)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        var p = ParticipantInStudy(uow, studyId, code);
        var a = uow.Assignments.Get(assignmentId);
        if (a is null || a.ParticipantId != p.Id)
            throw new NotFound("assignment not found");
        if (a.Status is AssignmentStatus.Completed or AssignmentStatus.Cancelled)
            throw new Conflict("this assignment is closed");
        if (contentId is { } cid)
        {
            var c = ContentInStudy(uow, studyId, cid);
            if (c.Status != ContentStatus.Approved)
                throw new Invalid("content must be approved before it is attached");
            var proto = uow.Protocols.Get(a.ProtocolId);
            if (proto is null || proto.Path != "interest_conversation")
                throw new Invalid("content is only used by the interest_conversation path");
            a.ContentId = c.Id;
            if (a.Status is AssignmentStatus.PendingTopic or AssignmentStatus.ContentPending)
                a.Status = AssignmentStatus.Ready;
        }
        if (status is not null)
        {
            if (status != "cancelled")
                throw new Invalid("status can only be set to cancelled");
            a.Status = AssignmentStatus.Cancelled;
        }
        uow.Commit();
        return AssignmentView(uow, a);
    }

    public static JsonArray MyAssignments(IUnitOfWork uow, Principal principal)
    {
        var p = RequireParticipant(principal);
        return Views(uow, uow.Assignments.ListForParticipant(p.Id));
    }

    private static Assignment OwnAssignment(IUnitOfWork uow, Principal principal, int assignmentId)
    {
        var p = RequireParticipant(principal);
        var a = uow.Assignments.Get(assignmentId);
        if (a is null || a.ParticipantId != p.Id)
            throw new NotFound("assignment not found");
        return a;
    }

    public static JsonObject ConfirmTopic(IUnitOfWork uow, Principal principal, int assignmentId, string? topic, string? freeText)
    {
        var a = OwnAssignment(uow, principal, assignmentId);
        if (a.Status is not (AssignmentStatus.PendingTopic or AssignmentStatus.ContentPending))
            throw new Conflict("the topic can no longer be changed for this assignment");
        if (string.IsNullOrWhiteSpace(topic) || topic.EnumerateRunes().Count() > 200)
            throw new Invalid("topic is required (up to 200 characters)");
        a.Topic = Fit(topic.Trim(), 200);
        var free = Head((freeText ?? "").Trim(), 2000);
        a.TopicFreeText = free.Length > 0 ? free : null;
        var proto = uow.Protocols.Get(a.ProtocolId);
        // the live avatar needs no prepared content: the confirmed topic is what it may talk about
        a.Status = proto is not null && proto.Path == "live_conversation" ? AssignmentStatus.Ready : AssignmentStatus.ContentPending;
        uow.Commit();
        return AssignmentView(uow, a);
    }

    private static JsonObject ShownQuestion(JsonObject q, string? name, string? topic) => new()
    {
        ["id"] = q["id"]?.DeepClone(),
        ["prompt"] = Personalize(q["prompt"], name, topic),
        ["options"] = new JsonArray(Items(q["options"]).Select(o => (JsonNode?)Personalize(o, name, topic)).ToArray()),
    };

    /// <summary>The content as the participant sees it: personalized, with signed media links and
    /// without the comprehension answers.</summary>
    public static JsonObject MyAssignmentContent(IUnitOfWork uow, IMediaSigner signer, Principal principal, int assignmentId)
    {
        var a = OwnAssignment(uow, principal, assignmentId);
        if (a.Status is not (AssignmentStatus.Ready or AssignmentStatus.InProgress) || a.ContentId is null)
            throw new NotFound("content is not ready yet");
        var c = uow.Content.Get(a.ContentId.Value);
        if (c is null || c.Status != ContentStatus.Approved)
            throw new NotFound("content is not ready yet");
        var name = uow.Profiles.Get(a.ParticipantId)?.DisplayName;
        var media = new Dictionary<string, ContentMedia>(StringComparer.Ordinal);
        foreach (var m in uow.Media.ListForContent(c.Id))
            media[m.Key] = m;
        var segments = new JsonArray();
        foreach (var node in Items(Get(c.Definition, "segments", new JsonArray())))
        {
            var seg = AsDict(node);
            var key = Json.Truthy(seg["media_key"]) ? Json.Str(seg["media_key"]) : "";
            var m = key is not null && media.TryGetValue(key, out var found) ? found : null;
            var q = seg["question"];
            segments.Add(new JsonObject
            {
                ["id"] = seg["id"]?.DeepClone(),
                ["text"] = Personalize(Get(seg, "text", ""), name, a.Topic),
                ["media_key"] = seg["media_key"]?.DeepClone(),
                ["media_url"] = m is null ? null : $"/media/{signer.Sign(m.Id)}",
                ["duration_s"] = seg["duration_s"]?.DeepClone(),
                ["face_layout"] = seg["face_layout"]?.DeepClone(),
                ["question"] = Json.Truthy(q) ? ShownQuestion(AsDict(q), name, a.Topic) : null,
            });
        }
        return new JsonObject
        {
            ["title"] = c.Title,
            ["face_id"] = c.FaceId,
            ["voice_id"] = c.VoiceId,
            ["start_segment"] = c.Definition["start_segment"]?.DeepClone(),
            ["post_segment"] = c.Definition["post_segment"]?.DeepClone(),
            ["segments"] = segments,
            ["comprehension"] = new JsonArray(Items(Get(c.Definition, "comprehension", new JsonArray()))
                .Select(q => (JsonNode?)ShownQuestion(AsDict(q), name, a.Topic)).ToArray()),
        };
    }

    // ---------- session hooks (called from the measurement use cases) ----------

    public static void BindAssignment(IUnitOfWork uow, Principal principal, Session session, int assignmentId)
    {
        var a = OwnAssignment(uow, principal, assignmentId);
        if (a.Status is not (AssignmentStatus.Ready or AssignmentStatus.InProgress))
            throw new Conflict($"assignment is not ready (status: {a.Status.Value()})");
        var proto = uow.Protocols.Get(a.ProtocolId);
        if (proto is null || proto.Status != ProtocolStatus.Published)
            throw new Conflict("the assigned protocol is not published");
        session.AssignmentId = a.Id;
        session.ProtocolId = proto.Id;
        a.Status = AssignmentStatus.InProgress;
    }

    public static void OnSessionEnd(IUnitOfWork uow, Session session)
    {
        if (session.AssignmentId is { } id && id != 0 && session.EndReason == "completed")
        {
            var a = uow.Assignments.Get(id);
            if (a is not null && a.Status == AssignmentStatus.InProgress)
                a.Status = AssignmentStatus.Completed;
        }
    }

    public static void ValidateComfortPayload(IUnitOfWork uow, Session session, JsonObject payload)
    {
        if (session.ProtocolId is not { } protocolId)
            return;
        var proto = uow.Protocols.Get(protocolId);
        var scaleMax = proto is null ? 5 : IntOf(Get(OrEmpty(proto.Definition["comfort"]), "scale_max", 5));
        var value = payload["value"];
        if (!IsIntLiteral(value) || !(1 <= PyInt(value) && PyInt(value) <= scaleMax))
            throw new Invalid($"comfort value must be an integer between 1 and {scaleMax}");
    }

    private static Protocol SessionProtocol(IUnitOfWork uow, Session session)
    {
        if (session.ProtocolId is not { } protocolId)
            throw new Conflict("this session runs no protocol");
        return uow.Protocols.Get(protocolId) ?? throw new Conflict("protocol not found");
    }

    private static Session OwnOpenSession(IUnitOfWork uow, Principal principal, int sessionId)
    {
        var p = RequireParticipant(principal);
        var s = uow.Sessions.Get(sessionId);
        if (s is null || s.ParticipantId != p.Id)
            throw new NotFound("session not found");
        s.EnsureOpen();
        return s;
    }

    public static (int Stored, int Correct) AddTrials(IUnitOfWork uow, Principal principal, int sessionId, IReadOnlyList<TrialInput> items)
    {
        var s = OwnOpenSession(uow, principal, sessionId);
        var proto = SessionProtocol(uow, s);
        if (proto.Path != "gradual_face")
            throw new Conflict("trials belong to the gradual_face path");
        if (!(1 <= items.Count && items.Count <= MaxTrialBatch))
            throw new Invalid($"1 to {MaxTrialBatch} trials per batch");
        var stages = Stages(proto.Definition);
        var rows = new List<Trial>();
        foreach (var it in items)
        {
            var idx = it.StageIndex;
            if (!(0 <= idx && idx < stages.Count))
                throw new Invalid("stage_index is out of range");
            var stage = AsDict(stages[idx]);
            var zone = it.Zone;
            if (!PyEquals(zone, stage["number_zone"]) || !Zones.Contains(zone))
                throw new Invalid($"trial zone {zone} does not match stage {idx} ({PyStr(stage["number_zone"])})");
            if (it.FaceLevel != IntOf(stage["face_level"]))
                throw new Invalid($"trial face_level does not match stage {idx}");
            var shown = it.NumberShown.Trim();
            if (shown.Length == 0)
                throw new Invalid("number_shown is required");
            var response = it.Response?.Trim();
            rows.Add(new Trial
            {
                SessionId = s.Id,
                StageIndex = idx,
                TrialIndex = it.TrialIndex,
                TMs = it.TMs,
                NumberShown = Fit(shown, 20),
                Zone = zone,
                Position = Json.CloneObj(it.Position),
                FaceLevel = IntOf(stage["face_level"]),
                Response = response is null ? null : Fit(response, 20),
                Correct = response == shown,
                ResponseMs = it.ResponseMs,
            });
        }
        var stored = uow.Trials.AddMany(rows);
        uow.Commit();
        return (stored, rows.Count(r => r.Correct));
    }

    public static StageResult SubmitStageResult(IUnitOfWork uow, Principal principal, int sessionId, int stageIndex, int? comfortValue)
    {
        var s = OwnOpenSession(uow, principal, sessionId);
        var proto = SessionProtocol(uow, s);
        if (proto.Path != "gradual_face")
            throw new Conflict("stage results belong to the gradual_face path");
        if (comfortValue is not null)
            ValidateComfortPayload(uow, s, new JsonObject { ["value"] = comfortValue });
        var results = uow.StageResults.ForSession(s.Id);
        var allTrials = uow.Trials.ForSession(s.Id);
        var marker = TrialMarker(results, allTrials);
        var attempt = allTrials.Where(t => t.StageIndex == stageIndex && t.Id > marker).ToList();
        var lastTrialId = allTrials.Count == 0 ? 0 : allTrials.Max(t => t.Id);
        var invalidShare = 0.0;
        if (attempt.Count > 0)
        {
            long t0 = attempt.Min(t => t.TMs);
            var seconds = FloatOf(Get(AsDict(Stages(proto.Definition)[stageIndex]), "trial_seconds", 8));
            var t1 = attempt.Max(t => t.TMs) + (long)(seconds * 1000);
            var window = uow.Samples.ForSession(s.Id).Where(x => x.Segment == "practice" && t0 <= x.TMs && x.TMs <= t1).ToList();
            if (window.Count > 0)
                invalidShare = (double)window.Count(x => x.Region == "uncertain") / window.Count;
        }
        var minOk = IntOf(Get(OrEmpty(proto.Definition["comfort"]), "min_ok", 3));
        var streak = 0;
        for (var i = results.Count - 1; i >= 0; i--)
        {
            if (results[i].ComfortValue is { } v && v < minOk)
                streak++;
            else
                break;
        }
        var decision = EvaluateStage(proto.Definition, stageIndex, attempt, comfortValue, PyMath.Round(invalidShare, 4), streak);
        var r = uow.StageResults.Add(new StageResult
        {
            SessionId = s.Id,
            StageIndex = stageIndex,
            Decision = decision.Decision,
            Reason = decision.Reason,
            CorrectRatio = decision.CorrectRatio,
            InvalidShare = decision.InvalidShare,
            ComfortValue = comfortValue,
            Trials = decision.Trials,
            NextStageIndex = decision.NextStageIndex,
            LastTrialId = lastTrialId,
        });
        uow.Commit();
        return r;
    }

    /// <summary>Id of the last trial that belongs to an earlier, already evaluated attempt.</summary>
    private static int TrialMarker(List<StageResult> results, List<Trial> trials)
    {
        if (results.Count == 0)
            return 0;
        var last = results[^1];
        return trials.Where(t => t.Id <= last.LastTrialId).Select(t => t.Id).DefaultIfEmpty(0).Max();
    }

    public static Answer SubmitAnswer(IUnitOfWork uow, Principal principal, int sessionId, string segmentId, string questionId, string kind, string option, int tMs)
    {
        var s = OwnOpenSession(uow, principal, sessionId);
        var proto = SessionProtocol(uow, s);
        if (proto.Path != "interest_conversation")
            throw new Conflict("answers belong to the interest_conversation path");
        if (!AnswerKinds.Contains(kind))
            throw new Invalid($"kind must be one of {MeasurementRules.TupleText(AnswerKinds)}");
        var a = uow.Assignments.Get(s.AssignmentId ?? 0);
        var c = a is { ContentId: { } contentId } && contentId != 0 ? uow.Content.Get(contentId) : null;
        if (c is null)
            throw new Conflict("no content is attached to this session");
        var name = uow.Profiles.Get(s.ParticipantId)?.DisplayName;
        string? next = null;
        bool? correct = null;
        if (kind == "interaction")
            next = NextSegment(c.Definition, segmentId, option, name, a!.Topic);
        else
            correct = ComprehensionCorrect(c.Definition, questionId, option, name, a!.Topic);
        var row = uow.Answers.Add(new Answer
        {
            SessionId = s.Id, SegmentId = Fit(segmentId, 60), QuestionId = Fit(questionId, 60), Kind = kind, Option = Fit(option, 200),
            Correct = correct, TMs = tMs, NextSegmentId = next is null ? null : Fit(next, 60),
        });
        uow.Commit();
        return row;
    }

    // ---------- outcomes ----------

    private static double? SegmentEyeShare(List<GazeSample> samples, List<SessionEvent> events, string label)
    {
        int? lastT = samples.Count == 0 ? null : samples.Max(x => x.TMs);
        var segs = MeasurementRules.SegmentsFromEvents(events, lastT).Where(sg => Json.Str(sg.Label) == label).ToList();
        if (segs.Count == 0)
            return null;
        var cov = MeasurementRules.Coverage(samples.Where(x => x.Segment == label), segs);
        return MeasurementRules.RegionShares(cov)?["eye"];
    }

    /// <summary>Adds protocol, outcomes and stages to a session summary. Safe for sessions without a protocol.</summary>
    public static JsonObject PracticeSummary(IUnitOfWork uow, Session s, JsonObject summary)
    {
        var proto = s.ProtocolId is { } protocolId && protocolId != 0 ? uow.Protocols.Get(protocolId) : null;
        var definition = proto?.Definition ?? [];
        var samples = uow.Samples.ForSession(s.Id);
        var events = uow.Events.ForSession(s.Id);
        var eye = OrEmpty(summary["eye_region_attention"]);
        var bShare = SegmentEyeShare(samples, events, "baseline");
        var pShare = SegmentEyeShare(samples, events, "post");
        var both = bShare is not null && pShare is not null;
        var gaze = new JsonObject
        {
            ["baseline_eye_share"] = F(bShare),
            ["post_eye_share"] = F(pShare),
            ["evaluable"] = Json.Truthy(eye["evaluable"]) && both,
            ["reason"] = Json.Truthy(eye["reason"]) ? eye["reason"]!.DeepClone() : both ? null : "baseline_or_post_missing",
        };
        var comp = uow.Answers.ForSession(s.Id).Where(a => a.Kind == "comprehension").ToList();
        var compCorrect = comp.Count(a => a.Correct == true);
        var comprehension = new JsonObject
        {
            ["answered"] = comp.Count,
            ["correct"] = compCorrect,
            ["share"] = comp.Count > 0 ? Json.Float(PyMath.Round((double)compCorrect / comp.Count, 4)) : null,
        };
        var trials = uow.Trials.ForSession(s.Id);
        var stageRows = uow.StageResults.ForSession(s.Id);
        var trialsCorrect = trials.Count(t => t.Correct);
        var numberTask = new JsonObject
        {
            ["trials"] = trials.Count,
            ["correct"] = trialsCorrect,
            ["share"] = trials.Count > 0 ? Json.Float(PyMath.Round((double)trialsCorrect / trials.Count, 4)) : null,
            ["stages_completed"] = stageRows.Count(r => r.Decision is "advance" or "complete"),
        };
        // isinstance(value, int): a bool counts, 4.0 does not
        var comfortValues = events.Where(e => e.Type == "comfort_answer").Select(e => PyInt(e.Payload["value"])).OfType<long>().ToList();
        var minOk = IntOf(Get(OrEmpty(definition["comfort"]), "min_ok", 3));
        var comfort = ComfortOutcome(comfortValues, minOk, events.Count(e => e.Type == "pause"), s.EndReason == "ended_early");
        summary["assignment_id"] = s.AssignmentId;
        summary["protocol"] = proto is null
            ? null
            : new JsonObject
            {
                ["id"] = proto.Id, ["name"] = proto.Name, ["version"] = proto.Version, ["path"] = proto.Path,
                ["definition"] = Json.CloneObj(proto.Definition),
            };
        var conversation = proto is not null && proto.Path == "live_conversation" ? LiveUseCases.ConversationOutcome(uow, s) : null;
        var improvement = Improvement(gaze, comprehension, numberTask, comfortValues, minOk, proto?.Path, conversation);
        summary["outcomes"] = new JsonObject
        {
            ["gaze"] = gaze,
            ["comprehension"] = comprehension,
            ["number_task"] = numberTask,
            ["comfort"] = comfort,
            ["conversation"] = conversation,
            ["improvement"] = improvement,
        };
        summary["stages"] = new JsonArray(stageRows.Select(r => (JsonNode?)new JsonObject
        {
            ["stage_index"] = r.StageIndex,
            ["decision"] = r.Decision,
            ["reason"] = r.Reason,
            ["correct_ratio"] = F(r.CorrectRatio),
            ["invalid_share"] = Json.Float(r.InvalidShare),
            ["comfort_value"] = r.ComfortValue,
            ["trials"] = r.Trials,
            ["next_stage_index"] = r.NextStageIndex,
        }).ToArray());
        return summary;
    }

    /// <summary>Trials (the first 500), answers and comfort answers for the staff session detail.</summary>
    public static JsonObject PracticeDetail(IUnitOfWork uow, Session s)
    {
        var events = uow.Events.ForSession(s.Id);
        return new JsonObject
        {
            ["trials"] = new JsonArray(uow.Trials.ForSession(s.Id).Take(500).Select(t => (JsonNode?)new JsonObject
            {
                ["stage_index"] = t.StageIndex, ["trial_index"] = t.TrialIndex, ["t_ms"] = t.TMs, ["number_shown"] = t.NumberShown,
                ["zone"] = t.Zone, ["position"] = Json.CloneObj(t.Position), ["face_level"] = t.FaceLevel, ["response"] = t.Response,
                ["correct"] = t.Correct, ["response_ms"] = t.ResponseMs,
            }).ToArray()),
            ["answers"] = new JsonArray(uow.Answers.ForSession(s.Id).Select(a => (JsonNode?)new JsonObject
            {
                ["segment_id"] = a.SegmentId, ["question_id"] = a.QuestionId, ["kind"] = a.Kind, ["option"] = a.Option,
                ["correct"] = a.Correct, ["t_ms"] = a.TMs, ["next_segment_id"] = a.NextSegmentId,
            }).ToArray()),
            ["comfort_answers"] = new JsonArray(events.Where(e => e.Type == "comfort_answer").Select(e =>
            {
                var o = new JsonObject { ["t_ms"] = e.TMs };
                foreach (var (k, v) in e.Payload)
                {
                    if (k is "value" or "stage_index" or "segment")
                        o[k] = v?.DeepClone();
                }
                return (JsonNode?)o;
            }).ToArray()),
        };
    }
}
