using System.Diagnostics;
using System.Text.Json.Nodes;
using EyeTracking.Domain;
using static EyeTracking.Application.Authz;

namespace EyeTracking.Application;

/// <summary>The configured live avatar providers (LiveProviders in live_use_cases.py).</summary>
public sealed record LiveProviders(IReplyGenerator Reply, ISpeechToText Stt, ILiveAvatarProvider Avatar);

/// <summary>Use cases for build step 7 (live_use_cases.py), the live interactive avatar (design p. 6).
/// A live conversation belongs to one session of a <c>live_conversation</c> protocol. The participant
/// speaks or types; the reply provider proposes an answer; the domain rules decide what the avatar
/// says. Audio is processed in memory only. Conversation text is kept after the conversation only
/// when the protocol allows it and the participant agreed; otherwise only counts and flags remain.
/// Paid replies count against the study's AI cost cap.</summary>
public static class LiveUseCases
{
    private static JsonNode? Ts(DateTime? t) => t is null ? null : JsonFormat.Timestamp(t.Value);

    /// <summary>Python's <c>info().get(key)</c> as a truth value.</summary>
    private static bool InfoFlag(JsonObject info, string key) => Json.Truthy(info[key]);

    private static Session OwnSession(IUnitOfWork uow, Principal principal, int sessionId)
    {
        var p = RequireParticipant(principal);
        var s = uow.Sessions.Get(sessionId);
        if (s is null || s.ParticipantId != p.Id)
            throw new NotFound("session not found");
        return s;
    }

    private static (JsonObject Cfg, Assignment A) LiveSetup(IUnitOfWork uow, Session s)
    {
        var proto = s.ProtocolId is { } pid && pid != 0 ? uow.Protocols.Get(pid) : null;
        if (proto is null || proto.Path != LiveRules.LivePath)
            throw new Conflict("this session is not a live conversation");
        var a = s.AssignmentId is { } aid && aid != 0 ? uow.Assignments.Get(aid) : null;
        if (a is null || string.IsNullOrEmpty(a.Topic))
            throw new Conflict("the conversation topic has not been confirmed");
        return (LiveRules.ValidateLive(proto.Definition["live"]), a);
    }

    private static (string? Name, List<string> Interests) Person(IUnitOfWork uow, int participantId)
    {
        var profile = uow.Profiles.Get(participantId);
        return (profile?.DisplayName, profile is null ? [] : [.. profile.Interests]);
    }

    private static JsonObject TurnView(LiveTurn t, bool withText = true) => new()
    {
        ["index"] = t.Index,
        ["role"] = t.Role,
        ["text"] = withText ? t.Text : null,
        ["chars"] = t.Chars,
        ["t_ms"] = t.TMs,
        ["flags"] = Json.Array(t.Flags),
        ["latency_ms"] = t.LatencyMs,
    };

    private static JsonObject ConvView(LiveConversation c, JsonObject cfg) => new()
    {
        ["id"] = c.Id,
        ["status"] = c.Status.Value(),
        ["topic"] = c.Topic,
        ["input_mode"] = c.InputMode,
        ["transcript_allowed"] = c.TranscriptAllowed,
        ["turns_used"] = c.TurnsUsed,
        ["turns_left"] = Math.Max(0, LiveRules.Setting(cfg, "max_turns") - c.TurnsUsed),
        ["end_reason"] = c.EndReason,
        ["started_at"] = Ts(c.StartedAt),
        ["ended_at"] = Ts(c.EndedAt),
        ["providers"] = new JsonObject { ["reply"] = c.ReplyProvider, ["speech"] = c.SttProvider, ["avatar"] = c.AvatarProvider },
    };

    private static JsonObject Limits(JsonObject cfg) =>
        new(new[] { "max_turns", "max_minutes", "max_reply_words", "max_participant_chars", "input_modes" }
            .Select(k => KeyValuePair.Create(k, (JsonNode?)cfg[k]!.DeepClone())));

    /// <summary>Closes the conversation; without the transcript agreement the stored text goes now.</summary>
    private static void Close(IUnitOfWork uow, IClock clock, LiveConversation c, string reason)
    {
        if (c.Status == ConversationStatus.Closed)
            return;
        c.Status = ConversationStatus.Closed;
        c.EndReason = reason;
        c.EndedAt = clock.Now();
        if (!c.TranscriptAllowed)
        {
            foreach (var t in uow.Live.Turns(c.Id))
                t.Text = null;
        }
    }

    /// <summary>Stores a turn: contact details and links are removed from the text; the count is of what was said.</summary>
    private static LiveTurn AddTurn(
        IUnitOfWork uow, LiveConversation c, string role, string text, int? tMs, List<string> flags, int? latencyMs = null, double cost = 0.0)
    {
        var index = uow.Live.Turns(c.Id).Count;
        return uow.Live.AddTurn(new LiveTurn
        {
            ConversationId = c.Id, SessionId = c.SessionId, Index = index, Role = role, Text = LiveRules.ScrubForStorage(text),
            Chars = text.EnumerateRunes().Count(), TMs = tMs, Flags = flags, LatencyMs = latencyMs, CostUnits = cost,
        });
    }

    // ---------- staff ----------

    public static JsonObject Status(IUnitOfWork uow, LiveProviders providers, Principal principal, int studyId)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher, StudyRole.Analyst);
        var b = AiUseCases.BudgetFor(uow, studyId);
        return new JsonObject
        {
            ["reply_provider"] = providers.Reply.Info(),
            ["speech_provider"] = providers.Stt.Info(),
            ["avatar_provider"] = providers.Avatar.Info(),
            ["estimates"] = new JsonObject
            {
                ["per_turn_units"] = Json.Float(providers.Reply.EstimateCost()),
                ["avatar_per_minute_units"] = Json.Float(providers.Avatar.EstimateCostPerMinute()),
            },
            ["budget"] = new JsonObject
            {
                ["cost_cap_units"] = Json.Float(b.CostCapUnits),
                ["spent_units"] = Json.Float(PyMath.Round(b.SpentUnits, 4)),
                ["remaining_units"] = Json.Float(PyMath.Round(b.Remaining(), 4)),
                ["send_free_text"] = b.SendFreeText,
            },
            ["open_conversations"] = uow.Live.OpenForStudy(studyId).Count,
            ["note"] = "Development providers are synthetic: sample rules, a sample face video and the browser's voice. No streaming avatar is connected.",
        };
    }

    /// <summary>The conversation for supervisors and analysts: counts, flags and the outcome; the
    /// text only when the protocol keeps transcripts and the participant agreed. A logged access.</summary>
    public static JsonObject StaffConversation(IUnitOfWork uow, Principal principal, int studyId, int sessionId)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher, StudyRole.Analyst);
        var s = uow.Sessions.Get(sessionId);
        if (s is null || s.StudyId != studyId)
            throw new NotFound("session not found");
        var c = uow.Live.ConversationForSession(s.Id) ?? throw new NotFound("this session has no live conversation");
        var proto = s.ProtocolId is { } pid && pid != 0 ? uow.Protocols.Get(pid) : null;
        var live = proto?.Definition["live"];
        var cfg = LiveRules.ValidateLive(Json.Truthy(live) ? live : new JsonObject());
        var turns = uow.Live.Turns(c.Id);
        var showText = c.TranscriptAllowed || c.Status == ConversationStatus.Open;
        ResearchUseCases.LogAccess(uow, principal, studyId, "live_transcript",
            new JsonObject { ["session_id"] = s.Id, ["text_shown"] = showText && c.TranscriptAllowed });
        uow.Commit();
        return new JsonObject
        {
            ["conversation"] = ConvView(c, cfg),
            ["turns"] = new JsonArray(turns.Select(t => (JsonNode?)TurnView(t, withText: c.TranscriptAllowed)).ToArray()),
            ["outcome"] = LiveRules.ConversationOutcome(turns, c.EndReason),
            ["cost_units"] = Json.Float(PyMath.Round(c.CostUnits, 5)),
            ["note"] = "Text is shown only when the protocol keeps transcripts and the participant agreed. Audio is never kept.",
        };
    }

    // ---------- participant ----------

    public static JsonObject Start(
        IUnitOfWork uow, LiveProviders providers, IClock clock, Principal principal, int sessionId, string inputMode, bool allowTranscript, int? tMs)
    {
        var s = OwnSession(uow, principal, sessionId);
        s.EnsureOpen();
        var (cfg, a) = LiveSetup(uow, s);
        var modes = cfg["input_modes"]!.AsArray().Select(m => (string)m!).ToList();
        if (!modes.Contains(inputMode))
            throw new Invalid("this conversation accepts: " + string.Join(", ", modes));
        if (inputMode == "speech" && !InfoFlag(providers.Stt.Info(), "configured"))
            throw new Conflict("speech is not available right now; please choose typing");
        if (!InfoFlag(providers.Reply.Info(), "configured"))
            throw new Conflict("provider_not_configured: the reply provider is not set up");
        var (name, _) = Person(uow, s.ParticipantId);
        var existing = uow.Live.ConversationForSession(s.Id);
        if (existing is not null)
        {
            if (existing.Status == ConversationStatus.Closed)
                throw new Conflict("this conversation has ended");
            var turns = uow.Live.Turns(existing.Id);
            return StartView(existing, new JsonArray(turns.Select(t => (JsonNode?)TurnView(t)).ToArray()), providers, cfg, resumed: true);
        }
        if (!InfoFlag(providers.Reply.Info(), "synthetic"))
            AiUseCases.BudgetFor(uow, s.StudyId).AssertAffordable(providers.Reply.EstimateCost());
        var c = uow.Live.AddConversation(new LiveConversation
        {
            SessionId = s.Id, StudyId = s.StudyId, ParticipantId = s.ParticipantId, Topic = a.Topic ?? "", InputMode = inputMode,
            TranscriptAllowed = Json.Truthy(cfg["store_transcript"]) && allowTranscript, ReplyProvider = PyText.Str(providers.Reply.Info()["name"]),
            AvatarProvider = PyText.Str(providers.Avatar.Info()["name"]), SttProvider = PyText.Str(providers.Stt.Info()["name"]), StartedAt = clock.Now(),
        });
        var opening = AddTurn(uow, c, "avatar", LiveRules.RenderLine(LiveRules.Line(cfg, "opening_line"), name, c.Topic), tMs, ["scripted_line", "opening"]);
        uow.Commit();
        return StartView(c, new JsonArray(TurnView(opening)), providers, cfg, resumed: false);
    }

    private static JsonObject StartView(LiveConversation c, JsonArray turns, LiveProviders providers, JsonObject cfg, bool resumed) => new()
    {
        ["conversation"] = ConvView(c, cfg),
        ["turns"] = turns,
        ["avatar"] = providers.Avatar.ClientConfig(LiveRules.Line(cfg, "avatar_id"), LiveRules.Line(cfg, "voice_id")),
        ["face_layout"] = cfg["face_layout"]?.DeepClone(),
        ["limits"] = Limits(cfg),
        ["resumed"] = resumed,
    };

    private static (Session S, JsonObject Cfg, Assignment A, LiveConversation C) OpenConversation(IUnitOfWork uow, Principal principal, int sessionId)
    {
        var s = OwnSession(uow, principal, sessionId);
        var (cfg, a) = LiveSetup(uow, s);
        var c = uow.Live.ConversationForSession(s.Id) ?? throw new Conflict("start the conversation first");
        if (c.Status == ConversationStatus.Closed)
            throw new Conflict("this conversation has ended");
        s.EnsureOpen();
        return (s, cfg, a, c);
    }

    /// <summary>Adds the closing line and closes. Returns the line's view taken before stored text is removed.</summary>
    private static JsonObject Finish(IUnitOfWork uow, IClock clock, LiveConversation c, JsonObject cfg, string? name, int? tMs, string reason, List<string> extraFlags)
    {
        var line = AddTurn(uow, c, "avatar", LiveRules.RenderLine(LiveRules.Line(cfg, "closing_line"), name, c.Topic), tMs,
            ["scripted_line", "closing", reason, .. extraFlags]);
        var view = TurnView(line);
        Close(uow, clock, c, reason);
        return view;
    }

    private static JsonObject Ended(LiveConversation c, JsonObject line) => new()
    {
        ["participant"] = null, ["avatar"] = line, ["turns_used"] = c.TurnsUsed, ["turns_left"] = 0, ["done"] = true, ["end_reason"] = c.EndReason, ["distress"] = false,
    };

    /// <summary>One exchange: the participant's typed text or recorded speech (<paramref name="audio"/>,
    /// transcribed in memory and never kept), then the avatar's reply as the guard rules allow it.</summary>
    public static async Task<JsonObject> TakeTurn(
        IUnitOfWork uow, LiveProviders providers, IClock clock, Principal principal, int sessionId, long expectTurn, int? tMs,
        string? text = null, byte[]? audio = null, string? contentType = null)
    {
        var (s, cfg, a, c) = OpenConversation(uow, principal, sessionId);
        if (expectTurn != c.TurnsUsed)
            throw new Conflict("this turn was already sent; reload the conversation");
        var (name, interests) = Person(uow, s.ParticipantId);
        var elapsedMin = (clock.Now() - c.StartedAt).TotalSeconds / 60.0;
        if (elapsedMin >= LiveRules.Setting(cfg, "max_minutes"))
        {
            var line = Finish(uow, clock, c, cfg, name, tMs, "time_limit", []);
            uow.Commit();
            return Ended(c, line);
        }
        var inFlags = new List<string>();
        if (audio is not null)
        {
            if (c.InputMode != "speech")
                throw new Invalid("this conversation was started for typing");
            var ctype = LiveRules.PyStrip((contentType ?? "").Split(';')[0]);
            if (!LiveRules.AudioTypes.Contains(ctype))
                throw new Invalid("unsupported audio type");
            if (audio.Length > LiveRules.MaxAudioBytes)
                throw new Invalid("the recording is too long; please say it in a shorter way");
            string heard;
            try
            {
                heard = await providers.Stt.Transcribe(audio, ctype, "en");
            }
            catch (SpeechError e)
            {
                throw new Invalid($"we could not turn that into text ({e.Message}); please try again or type");
            }
            finally
            {
                // nothing keeps the recording
                Array.Clear(audio);
            }
            text = heard;
            inFlags.Add("speech");
            if (InfoFlag(providers.Stt.Info(), "synthetic"))
                inFlags.Add("sample_speech");
        }
        else
        {
            inFlags.Add("typed");
        }
        var (ptext, pflags) = LiveRules.PrepareParticipantText(text, LiveRules.Setting(cfg, "max_participant_chars"));
        var budget = AiUseCases.BudgetFor(uow, s.StudyId);
        if (!InfoFlag(providers.Reply.Info(), "synthetic"))
        {
            try
            {
                budget.AssertAffordable(providers.Reply.EstimateCost());
            }
            catch (Invalid)
            {
                // the cap is reached: the conversation ends politely with the closing line
                AddTurn(uow, c, "participant", ptext, tMs, [.. inFlags, .. pflags]);
                var line = Finish(uow, clock, c, cfg, name, tMs, "budget", []);
                c.TurnsUsed += 1;
                uow.Commit();
                return Ended(c, line);
            }
        }
        var history = uow.Live.Turns(c.Id).Select(t => (t.Role, t.Text ?? "")).Append(("participant", LiveRules.ScrubForStorage(ptext) ?? ""));
        var freeText = budget.SendFreeText ? a.TopicFreeText : null;
        var system = LiveRules.SystemPrompt(cfg, c.Topic, name, interests, freeText);
        var started = Stopwatch.StartNew();
        JsonObject? data = null;
        JsonObject meta = [];
        var providerFlags = new List<string>();
        try
        {
            (data, meta) = await providers.Reply.Reply(system, LiveRules.ConversationBlock(history), c.Topic);
        }
        catch (ReplyRefused)
        {
            providerFlags.Add("refusal");
        }
        catch (ReplyError)
        {
            providerFlags.Add("provider_error");
        }
        var latency = (int)started.ElapsedMilliseconds;
        var g = LiveRules.GuardReply(data, cfg, name, c.Topic, c.OffTopicStreak);
        if (g.ParticipantOnTopic == true)
            pflags.Add("participant_on_topic");
        else if (g.ParticipantOnTopic == false)
            pflags.Add("participant_off_topic");
        if (g.Distress)
            pflags.Add("distress");
        c.OffTopicStreak = g.ParticipantOnTopic == false ? c.OffTopicStreak + 1 : 0;
        var cost = Json.Truthy(meta["cost_actual_units"]) ? PracticeRules.FloatOf(meta["cost_actual_units"]) : 0.0;
        if (cost != 0)
        {
            budget.SpentUnits += cost;
            uow.AiBudgets.Save(budget);
            c.CostUnits += cost;
        }
        var part = AddTurn(uow, c, "participant", ptext, tMs, [.. inFlags, .. pflags]);
        c.TurnsUsed += 1;
        var reason = g.EndReason;
        if (reason is null && c.TurnsUsed >= LiveRules.Setting(cfg, "max_turns"))
            reason = "turn_limit";
        var avatar = reason switch
        {
            "participant" => AddTurn(uow, c, "avatar", g.Text, tMs, [.. g.Flags, .. providerFlags, "closing"], latency, cost),
            "turn_limit" => AddTurn(uow, c, "avatar", LiveRules.RenderLine(LiveRules.Line(cfg, "closing_line"), name, c.Topic), tMs,
                ["scripted_line", "closing", "turn_limit", .. providerFlags], latency, cost),
            _ => AddTurn(uow, c, "avatar", g.Text, tMs, [.. g.Flags, .. providerFlags], latency, cost),
        };
        // the participant hears and reads this reply now; stored text may be removed right after
        var (partView, avatarView) = (TurnView(part), TurnView(avatar));
        if (reason is "participant" or "turn_limit")
            Close(uow, clock, c, reason);
        uow.Commit();
        return new JsonObject
        {
            ["participant"] = partView,
            ["avatar"] = avatarView,
            ["turns_used"] = c.TurnsUsed,
            ["turns_left"] = Math.Max(0, LiveRules.Setting(cfg, "max_turns") - c.TurnsUsed),
            ["done"] = c.Status == ConversationStatus.Closed,
            ["end_reason"] = c.EndReason,
            ["distress"] = g.Distress,
        };
    }

    public static JsonObject End(IUnitOfWork uow, IClock clock, Principal principal, int sessionId, int? tMs)
    {
        var (s, cfg, _, c) = OpenConversation(uow, principal, sessionId);
        var (name, _) = Person(uow, s.ParticipantId);
        var line = Finish(uow, clock, c, cfg, name, tMs, "participant_ended", []);
        uow.Commit();
        return new JsonObject { ["avatar"] = line, ["turns_used"] = c.TurnsUsed, ["done"] = true, ["end_reason"] = c.EndReason };
    }

    public static JsonObject MyConversation(IUnitOfWork uow, Principal principal, int sessionId)
    {
        var s = OwnSession(uow, principal, sessionId);
        var (cfg, _) = LiveSetup(uow, s);
        var c = uow.Live.ConversationForSession(s.Id);
        return new JsonObject
        {
            ["conversation"] = c is null ? null : ConvView(c, cfg),
            ["turns"] = c is null ? new JsonArray() : new JsonArray(uow.Live.Turns(c.Id).Select(t => (JsonNode?)TurnView(t)).ToArray()),
            ["limits"] = Limits(cfg),
            ["store_transcript_offered"] = cfg["store_transcript"]!.DeepClone(),
            ["input_modes"] = cfg["input_modes"]!.DeepClone(),
        };
    }

    // ---------- hooks for earlier steps ----------

    /// <summary>Closes the session's open conversation when the session ends.</summary>
    public static void CloseOnSessionEnd(IUnitOfWork uow, IClock clock, Session session)
    {
        var c = uow.Live.ConversationForSession(session.Id);
        if (c is not null && c.Status == ConversationStatus.Open)
            Close(uow, clock, c, "session_ended");
    }

    /// <summary>The conversation outcome of a live_conversation session (practice summaries).</summary>
    public static JsonObject ConversationOutcome(IUnitOfWork uow, Session session)
    {
        var c = uow.Live.ConversationForSession(session.Id);
        return c is null ? LiveRules.ConversationOutcome([], null) : LiveRules.ConversationOutcome(uow.Live.Turns(c.Id), c.EndReason);
    }

    /// <summary>The conversation part of the supervisor's live view (monitor_block); null when the
    /// session has no conversation. Counts and flags only, never the text.</summary>
    public static JsonObject? MonitorBlock(IUnitOfWork uow, int sessionId)
    {
        var c = uow.Live.ConversationForSession(sessionId);
        if (c is null)
            return null;
        var turns = uow.Live.Turns(c.Id);
        var last = turns.Count > 0 ? turns[^1] : null;
        return new JsonObject
        {
            ["status"] = c.Status.Value(),
            ["input_mode"] = c.InputMode,
            ["turns_used"] = c.TurnsUsed,
            ["distress"] = turns.Count(t => t.Role == "participant" && t.Flags.Contains("distress")),
            ["redirects"] = turns.Count(t => t.Role == "avatar" && (t.Flags.Contains("redirect_line") || t.Flags.Contains("fallback_line"))),
            ["last_turn"] = last is null ? null : new JsonObject { ["role"] = last.Role, ["flags"] = Json.Array(last.Flags), ["t_ms"] = last.TMs },
            ["end_reason"] = c.EndReason,
        };
    }
}
