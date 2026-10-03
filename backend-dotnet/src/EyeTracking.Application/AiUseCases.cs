using System.Text.Json;
using System.Text.Json.Nodes;
using EyeTracking.Domain;
using static EyeTracking.Application.Authz;
using static EyeTracking.Domain.PracticeRules;

namespace EyeTracking.Application;

/// <summary>The configured providers and the background worker's settings (Providers in ai_use_cases.py).</summary>
public sealed record AiProviders(ITextGenerator Text, IVideoGenerator Video, bool WorkerEnabled = false, int WorkerIntervalS = 5);

/// <summary>Use cases for build step 5 (ai_use_cases.py): AI text and video generation jobs, the review
/// flow, the per-study budget and the job runner. A provider only ever receives the topic, display
/// name, interests and script constraints (free text only when the study allows it), never the
/// camera image, the login email or gaze data; a paid job needs an admin-set cap it fits under; and
/// generated content stays a draft until a researcher reviews, approves and attaches it.</summary>
public static class AiUseCases
{
    private static JsonNode? Ts(DateTime? t) => t is null ? null : JsonFormat.Timestamp(t.Value);

    /// <summary>Free text cut to its SQL Server column (SQLite kept any length).</summary>
    private static string Fit(string text, int max)
    {
        if (text.Length <= max)
            return text;
        var cut = text[..max];
        return char.IsHighSurrogate(cut[^1]) ? cut[..^1] : cut;
    }

    /// <summary>Python's <c>datetime.utcnow()</c> at the precision of the datetime2(6) columns.</summary>
    private static DateTime UtcNow()
    {
        var ticks = DateTime.UtcNow.Ticks;
        return new DateTime(ticks - ticks % 10, DateTimeKind.Unspecified);
    }

    /// <summary>Python's <c>float(v or 0)</c> of a meta value.</summary>
    private static double FloatOr0(JsonNode? v) => Json.Truthy(v) ? FloatOf(v) : 0.0;

    /// <summary>Python's <c>len(v)</c> of a definition value.</summary>
    private static int Len(JsonNode? v) => v switch
    {
        JsonArray a => a.Count,
        JsonObject o => o.Count,
        _ when Json.Str(v) is { } s => s.EnumerateRunes().Count(),
        _ => throw new InvalidOperationException($"object of type {PyText.Str(v)} has no len()"),
    };

    /// <summary>Python's <c>d[key]</c>: a missing key fails (KeyError).</summary>
    private static JsonNode? Required(JsonObject d, string key) =>
        d.TryGetPropertyValue(key, out var value) ? value : throw new KeyNotFoundException($"'{key}'");

    private static string Text(JsonNode? v) => Json.Str(v) ?? throw new InvalidOperationException("expected text");

    // ---------- status and budget ----------

    public static AiBudget BudgetFor(IUnitOfWork uow, int studyId) => uow.AiBudgets.Get(studyId) ?? new AiBudget { StudyId = studyId };

    private static JsonObject BudgetView(AiBudget b) => new()
    {
        ["cost_cap_units"] = Json.Float(b.CostCapUnits),
        ["spent_units"] = Json.Float(PyMath.Round(b.SpentUnits, 4)),
        ["remaining_units"] = Json.Float(PyMath.Round(b.Remaining(), 4)),
        ["unit"] = "usd_estimate",
    };

    public static JsonObject Status(IUnitOfWork uow, AiProviders providers, Principal principal, int studyId)
    {
        RequireStudyAccess(principal, studyId);
        var b = BudgetFor(uow, studyId);
        return new JsonObject
        {
            ["text_provider"] = providers.Text.Info(),
            ["video_provider"] = providers.Video.Info(),
            ["budget"] = BudgetView(b),
            ["worker"] = new JsonObject { ["enabled"] = providers.WorkerEnabled, ["interval_s"] = providers.WorkerIntervalS },
            ["send_free_text"] = b.SendFreeText,
        };
    }

    public static JsonObject SetBudget(IUnitOfWork uow, Principal principal, int studyId, double? costCapUnits, bool? sendFreeText)
    {
        RequireRole(principal, Role.Admin);
        if (uow.Studies.Get(studyId) is null)
            throw new NotFound("study not found");
        var b = BudgetFor(uow, studyId);
        if (costCapUnits is { } cap)
        {
            if (cap < 0 || cap > 1_000_000)
                throw new Invalid("cost_cap_units must be between 0 and 1000000");
            b.CostCapUnits = cap;
        }
        if (sendFreeText is { } send)
            b.SendFreeText = send;
        b = uow.AiBudgets.Save(b);
        ResearchUseCases.LogAccess(uow, principal, studyId, "ai_budget_changed",
            new JsonObject { ["cost_cap_units"] = Json.Float(b.CostCapUnits), ["send_free_text"] = b.SendFreeText });
        uow.Commit();
        var view = BudgetView(b);
        view["send_free_text"] = b.SendFreeText;
        return view;
    }

    // ---------- jobs ----------

    private static JsonObject JobView(IUnitOfWork uow, GenerationJob j)
    {
        var content = uow.Content.Get(j.ContentId);
        return new JsonObject
        {
            ["id"] = j.Id,
            ["kind"] = j.Kind,
            ["status"] = j.Status,
            ["provider"] = j.Provider,
            ["content_id"] = j.ContentId,
            ["content_title"] = content?.Title,
            ["assignment_id"] = j.AssignmentId,
            ["segment_id"] = j.SegmentId,
            ["attempts"] = j.Attempts,
            ["max_attempts"] = j.MaxAttempts,
            ["cost_estimate_units"] = Json.Float(j.CostEstimateUnits),
            ["cost_actual_units"] = Json.Float(j.CostActualUnits),
            ["error"] = j.Error,
            ["created_at"] = Ts(j.CreatedAt),
            ["started_at"] = Ts(j.StartedAt),
            ["finished_at"] = Ts(j.FinishedAt),
            ["next_attempt_at"] = Ts(j.NextAttemptAt),
            ["request"] = Json.CloneObj(j.Request),
            ["result"] = Json.CloneObj(j.Result),
        };
    }

    public static JsonObject CreateTextJob(
        IUnitOfWork uow, AiProviders providers, IClock clock, Principal principal, int studyId, int? assignmentId, string? topic, string? displayName,
        IReadOnlyList<string>? interests, int interactionPoints, int lengthSeconds, string? title, string? faceId, string? voiceId)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        if (uow.Studies.Get(studyId) is null)
            throw new NotFound("study not found");
        var info = providers.Text.Info();
        if (!Json.Truthy(info["configured"]))
            throw new Invalid($"provider_not_configured: text provider {PyText.Str(info["name"])} has no key");
        var b = BudgetFor(uow, studyId);
        string? freeText = null;
        if (assignmentId is { } aid)
        {
            var a = uow.Assignments.Get(aid);
            if (a is null || a.StudyId != studyId)
                throw new NotFound("assignment not found");
            if (a.Status is not (AssignmentStatus.PendingTopic or AssignmentStatus.ContentPending))
                throw new Conflict($"assignment is {a.Status.Value()}; text is generated only while content is pending");
            var profile = uow.Profiles.Get(a.ParticipantId);
            topic = string.IsNullOrEmpty(topic) ? a.Topic : topic;
            displayName ??= profile?.DisplayName;
            interests ??= profile is null ? [] : [.. profile.Interests];
            if (b.SendFreeText)
                freeText = a.TopicFreeText;
        }
        var req = new TextRequest(
            (topic ?? "").Trim(), string.IsNullOrEmpty(displayName) ? null : displayName,
            (interests ?? []).Where(i => i.Trim().Length > 0).Select(i => i.Trim()).ToList(), interactionPoints, lengthSeconds, freeText);
        req.Validate();
        var estimate = providers.Text.EstimateCost(req);
        b.AssertAffordable(estimate);
        var definition = new JsonObject
        {
            ["start_segment"] = "s1",
            ["post_segment"] = "s1",
            ["segments"] = new JsonArray(new JsonObject { ["id"] = "s1", ["text"] = "(generating…)", ["duration_s"] = 10, ["question"] = null }),
            ["comprehension"] = new JsonArray(),
        };
        var content = uow.Content.Add(new ContentItem
        {
            StudyId = studyId, Title = Fit(AiRules.Head(string.IsNullOrEmpty(title) ? $"AI draft: {req.Topic}" : title, 200), 200),
            Definition = definition, TopicTags = [req.Topic.ToLowerInvariant()], FaceId = Fit(faceId ?? "", 100), VoiceId = Fit(voiceId ?? "", 100),
            CreatedAt = clock.Now(), UpdatedAt = clock.Now(),
        });
        var name = PyText.Str(info["name"]);
        var job = uow.Jobs.Add(new GenerationJob
        {
            StudyId = studyId, Kind = "text", Provider = name, ContentId = content.Id, AssignmentId = assignmentId,
            CostEstimateUnits = estimate, Request = req.Minimized(), CreatedAt = clock.Now(),
        });
        ResearchUseCases.LogAccess(uow, principal, studyId, "ai_job_created",
            new JsonObject { ["job_id"] = job.Id, ["kind"] = "text", ["provider"] = name, ["estimate"] = Json.Float(estimate) });
        uow.Commit();
        return JobView(uow, job);
    }

    public static JsonArray CreateVideoJobs(
        IUnitOfWork uow, AiProviders providers, IClock clock, Principal principal, int studyId, int contentId, IReadOnlyList<string>? segmentIds,
        string? faceId, string? voiceId)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        var c = uow.Content.Get(contentId);
        if (c is null || c.StudyId != studyId)
            throw new NotFound("content not found");
        c.EnsureDraft();
        if (!c.TextReviewed)
            throw new Conflict("mark the text as reviewed before generating videos");
        var info = providers.Video.Info();
        if (!Json.Truthy(info["configured"]))
            throw new Invalid($"provider_not_configured: video provider {PyText.Str(info["name"])} has no key");
        var face = string.IsNullOrEmpty(faceId) ? c.FaceId : faceId;
        var voice = string.IsNullOrEmpty(voiceId) ? c.VoiceId : voiceId;
        if (!string.IsNullOrEmpty(faceId) || !string.IsNullOrEmpty(voiceId))
        {
            c.FaceId = Fit(face, 100);
            c.VoiceId = Fit(voice, 100);
        }
        var present = uow.Media.ListForContent(c.Id).Select(m => m.Key).ToHashSet(StringComparer.Ordinal);
        var wanted = (segmentIds ?? []).ToHashSet(StringComparer.Ordinal);
        var targets = Items(Get(c.Definition, "segments", new JsonArray())).Select(AsDict)
            .Where(seg => Json.Truthy(seg["media_key"]) && !(Json.Str(seg["media_key"]) is { } key && present.Contains(key))
                          && (wanted.Count == 0 || (Json.Str(Required(seg, "id")) is { } id && wanted.Contains(id))))
            .ToList();
        if (targets.Count == 0)
            throw new Invalid("every selected segment already has media");
        var b = BudgetFor(uow, studyId);
        double Estimate(JsonObject seg) => providers.Video.EstimateCost(Text(Get(seg, "text", "")), FloatOr0(seg["duration_s"]));
        var total = 0.0;
        foreach (var seg in targets)
            total += Estimate(seg);
        b.AssertAffordable(total);
        var name = PyText.Str(info["name"]);
        var jobs = new List<GenerationJob>();
        foreach (var seg in targets)
        {
            var est = Estimate(seg);
            var segmentId = Required(seg, "id");
            jobs.Add(uow.Jobs.Add(new GenerationJob
            {
                StudyId = studyId, Kind = "video", Provider = name, ContentId = c.Id, SegmentId = Fit(PyText.Str(segmentId), 60),
                CostEstimateUnits = est, CreatedAt = clock.Now(),
                Request = new JsonObject
                {
                    ["segment_id"] = segmentId?.DeepClone(),
                    ["media_key"] = seg["media_key"]?.DeepClone(),
                    ["face_id"] = face,
                    ["voice_id"] = voice,
                    ["chars"] = Text(Get(seg, "text", "")).EnumerateRunes().Count(),
                },
            }));
        }
        ResearchUseCases.LogAccess(uow, principal, studyId, "ai_job_created", new JsonObject
        {
            ["job_ids"] = Json.Array(jobs.Select(j => j.Id)), ["kind"] = "video", ["provider"] = name, ["estimate"] = Json.Float(PyMath.Round(total, 4)),
        });
        uow.Commit();
        return new JsonArray(jobs.Select(j => (JsonNode?)JobView(uow, j)).ToArray());
    }

    public static JsonArray ListJobs(IUnitOfWork uow, Principal principal, int studyId, string? status, long? contentId)
    {
        RequireStudyAccess(principal, studyId);
        return new JsonArray(uow.Jobs.ListForStudy(studyId, status, contentId).Select(j => (JsonNode?)JobView(uow, j)).ToArray());
    }

    private static GenerationJob StudyJob(IUnitOfWork uow, Principal principal, int studyId, int jobId)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        var j = uow.Jobs.Get(jobId);
        if (j is null || j.StudyId != studyId)
            throw new NotFound("job not found");
        return j;
    }

    public static JsonObject GetJob(IUnitOfWork uow, Principal principal, int studyId, int jobId)
    {
        RequireStudyAccess(principal, studyId);
        var j = uow.Jobs.Get(jobId);
        if (j is null || j.StudyId != studyId)
            throw new NotFound("job not found");
        return JobView(uow, j);
    }

    public static JsonObject CancelJob(IUnitOfWork uow, Principal principal, int studyId, int jobId)
    {
        var j = StudyJob(uow, principal, studyId, jobId);
        j.Cancel();
        uow.Commit();
        return JobView(uow, j);
    }

    public static JsonObject RetryJob(IUnitOfWork uow, IClock clock, Principal principal, int studyId, int jobId)
    {
        var j = StudyJob(uow, principal, studyId, jobId);
        j.Retry(clock.Now());
        uow.Commit();
        return JobView(uow, j);
    }

    /// <summary>The researcher has read the generated text; only then can videos be generated.
    /// Editing the definition afterwards clears the flag again (PracticeUseCases.UpdateContent).</summary>
    public static ContentItem MarkTextReviewed(IUnitOfWork uow, IClock clock, Principal principal, int studyId, int contentId)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        var c = uow.Content.Get(contentId);
        if (c is null || c.StudyId != studyId)
            throw new NotFound("content not found");
        c.EnsureDraft();
        ValidateContent(c.Definition);
        c.TextReviewed = true;
        c.UpdatedAt = clock.Now();
        uow.Commit();
        return c;
    }

    // ---------- worker ----------

    /// <summary>Python's <c>type(exc).__name__</c> for the job's error text.</summary>
    private static string ErrorName(Exception e) => e switch
    {
        TerminalGenerationError => "TerminalGenerationError",
        GenerationError g => g.Kind,
        JsonException => "JSONDecodeError",
        KeyNotFoundException => "KeyError",
        ArgumentException => "ValueError",
        _ => e.GetType().Name,
    };

    /// <summary>Processes queued jobs whose backoff has passed, each committed on its own. Safe to call
    /// from the worker (no principal) or the API (a researcher of <paramref name="studyId"/>, which
    /// stops at the first queued job of another study).</summary>
    public static async Task<JsonObject> RunJobs(
        IUnitOfWork uow, AiProviders providers, IMediaStore store, IClock clock, int maxJobs = 5, Principal? principal = null, int? studyId = null)
    {
        if (principal is not null && studyId is not null)
            RequireStudyAccess(principal, studyId.Value, StudyRole.Researcher);
        int processed = 0, succeeded = 0, failed = 0;
        while (processed < maxJobs)
        {
            var now = clock.Now();
            var j = uow.Jobs.NextQueued(now);
            if (j is null || (studyId is not null && j.StudyId != studyId))
                break;
            j.Status = "running";
            j.StartedAt = now;
            uow.Commit();
            processed++;
            try
            {
                await Execute(uow, providers, store, j);
                j.Status = "succeeded";
                j.FinishedAt = clock.Now();
                var b = BudgetFor(uow, j.StudyId);
                b.SpentUnits = PyMath.Round(b.SpentUnits + j.CostActualUnits, 4);
                uow.AiBudgets.Save(b);
                succeeded++;
            }
            catch (Exception e)
            {
                // every failure is recorded on the job; a refusal or an invalid result is not retried
                var terminal = e is TerminalGenerationError or Invalid;
                j.MarkFailure($"{ErrorName(e)}: {e.Message}", clock.Now(), terminal);
                if (j.Status == "failed")
                    failed++;
            }
            uow.AccessLog.Add(new AccessLogEntry
            {
                StudyId = j.StudyId, UserId = principal?.UserId ?? 0, Role = principal?.Role.Value() ?? "worker", Action = "ai_job_run",
                Detail = new JsonObject
                {
                    ["job_id"] = j.Id, ["kind"] = j.Kind, ["status"] = j.Status, ["provider"] = j.Provider, ["cost_actual_units"] = Json.Float(j.CostActualUnits),
                },
            });
            uow.Commit();
        }
        return new JsonObject { ["processed"] = processed, ["succeeded"] = succeeded, ["failed"] = failed };
    }

    private static async Task Execute(IUnitOfWork uow, AiProviders providers, IMediaStore store, GenerationJob j)
    {
        var c = uow.Content.Get(j.ContentId) ?? throw new Invalid("content of this job no longer exists");
        var r = j.Request;
        if (j.Kind == "text")
        {
            var req = new TextRequest(
                Text(Required(r, "topic")), Json.Str(r["display_name"]),
                Json.Truthy(r["interests"]) ? Items(r["interests"]).Select(Text).ToList() : [],
                IntOf(Get(r, "interaction_points", 2)), IntOf(Get(r, "length_seconds", 90)));
            if (Json.Truthy(r["free_text_included"]) && j.AssignmentId is { } aid && aid != 0)
                req = req with { FreeText = uow.Assignments.Get(aid)?.TopicFreeText };
            var (raw, meta) = await providers.Text.Generate(req);
            var definition = AiRules.AssignMediaKeys(AiRules.BranchesToDict(raw));
            ValidateContent(definition);
            c.EnsureDraft();
            c.Definition = definition;
            c.TextReviewed = false;
            c.UpdatedAt = UtcNow();
            j.CostActualUnits = FloatOr0(meta["cost_actual_units"]);
            j.Result = new JsonObject
            {
                ["segments"] = Len(Get(definition, "segments", new JsonArray())),
                ["comprehension"] = Len(Get(definition, "comprehension", new JsonArray())),
                ["model"] = meta["model"]?.DeepClone(),
                ["input_tokens"] = meta["input_tokens"]?.DeepClone(),
                ["output_tokens"] = meta["output_tokens"]?.DeepClone(),
            };
        }
        else
        {
            // the job's segment_id column is cut to 60 characters; the request keeps the full id
            JsonNode? segmentId = r.TryGetPropertyValue("segment_id", out var full) ? full : j.SegmentId;
            var seg = Items(Get(c.Definition, "segments", new JsonArray())).Select(AsDict)
                .FirstOrDefault(s => PyEquals(Required(s, "id"), segmentId))
                ?? throw new Invalid("segment no longer exists in the content");
            var (data, contentType, meta) = await providers.Video.Generate(
                Text(Get(seg, "text", "")), Json.Str(Get(r, "face_id", "")) ?? "", Json.Str(Get(r, "voice_id", "")) ?? "");
            var key = Json.Truthy(seg["media_key"]) ? PyText.Str(seg["media_key"]) : $"{PyText.Str(Required(seg, "id"))}.webm";
            var rel = store.Save($"study-{c.StudyId}/content-{c.Id}/{key}", data);
            var existing = uow.Media.ByKey(c.Id, key);
            if (existing is not null)
            {
                existing.Path = rel;
                existing.ContentType = contentType;
                existing.Size = data.Length;
            }
            else
            {
                uow.Media.Add(new ContentMedia { ContentId = c.Id, Key = key, Path = rel, ContentType = contentType, Size = data.Length });
            }
            j.CostActualUnits = FloatOr0(meta["cost_actual_units"]);
            j.Result = new JsonObject
            {
                ["media_key"] = key, ["content_type"] = contentType, ["size"] = data.Length,
                ["duration_s"] = meta["duration_s"]?.DeepClone(), ["note"] = meta["note"]?.DeepClone(),
            };
        }
    }
}
