using System.Linq.Expressions;
using System.Text.Json.Nodes;
using EyeTracking.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace EyeTracking.Infrastructure.Db;

/// <summary>SQL Server schema, the same tables and columns as backend/eyetracking/infrastructure/orm.py.
/// Columns are snake_case, enums are stored as their snake_case value, free-form JSON as nvarchar(max).
/// Foreign keys never cascade: deletion order is explicit in the code (see purge rules).</summary>
public sealed class EyeTrackingDb(DbContextOptions<EyeTrackingDb> options) : DbContext(options)
{
    protected override void ConfigureConventions(ModelConfigurationBuilder c)
    {
        c.Properties<DateTime>().HaveColumnType("datetime2(6)");
        c.Properties<JsonObject>().HaveConversion<JsonObjectConverter, JsonNodeComparer<JsonObject>>().HaveColumnType("nvarchar(max)");
        c.Properties<JsonArray>().HaveConversion<JsonArrayConverter, JsonNodeComparer<JsonArray>>().HaveColumnType("nvarchar(max)");
        c.Properties<List<string>>().HaveConversion<StringListConverter, StringListComparer>().HaveColumnType("nvarchar(max)");
        Enum<Role>(c);
        Enum<StudyRole>(c);
        Enum<ResponseMode>(c);
        Enum<SessionStatus>(c);
        Enum<ProtocolStatus>(c);
        Enum<ContentStatus>(c);
        Enum<AssignmentStatus>(c);
        Enum<ConversationStatus>(c);
    }

    private static void Enum<T>(ModelConfigurationBuilder c) where T : struct, Enum =>
        c.Properties<T>().HaveConversion<SnakeEnumConverter<T>>().HaveMaxLength(20).AreUnicode(false);

    protected override void OnModelCreating(ModelBuilder b)
    {
        // ---------- step 1 ----------
        Table<User>(b, "users", e =>
        {
            Str(e, x => x.Email, 255);
            Str(e, x => x.PasswordHash, 255);
            e.HasIndex(x => x.Email).IsUnique();
        });
        Table<Study>(b, "studies", e =>
        {
            Str(e, x => x.Name, 200);
            Str(e, x => x.RetentionPolicy, 20);
        });
        Table<StudyMembership>(b, "study_memberships", e =>
        {
            Fk<StudyMembership, Study>(e, x => x.StudyId);
            Fk<StudyMembership, User>(e, x => x.UserId);
            e.HasIndex(x => new { x.StudyId, x.UserId }).IsUnique().HasDatabaseName("uq_membership");
        });
        Table<Participant>(b, "participants", e =>
        {
            Str(e, x => x.Code, 20, exact: true);
            Fk<Participant, Study>(e, x => x.StudyId);
            Fk<Participant, User>(e, x => x.UserId);
            e.HasIndex(x => x.UserId).IsUnique();
            e.HasIndex(x => new { x.StudyId, x.Code }).IsUnique().HasDatabaseName("uq_participant_code");
        });
        Table<Invitation>(b, "invitations", e =>
        {
            Str(e, x => x.Token, 64, exact: true);
            Str(e, x => x.Code, 20, exact: true);
            Str(e, x => x.InviteeEmail, 255, required: false);
            Fk<Invitation, Study>(e, x => x.StudyId);
            Fk<Invitation, User>(e, x => x.CreatedBy);
            e.HasIndex(x => x.Token).IsUnique();
            e.HasIndex(x => new { x.StudyId, x.Code }).IsUnique().HasDatabaseName("uq_invitation_code");
        });
        Table<InformationSheet>(b, "information_sheets", e =>
        {
            Fk<InformationSheet, Study>(e, x => x.StudyId);
            e.HasIndex(x => new { x.StudyId, x.Version }).IsUnique().HasDatabaseName("uq_sheet_version");
        });
        Table<Consent>(b, "consents", e => Fk<Consent, Participant>(e, x => x.ParticipantId));
        Table<Profile>(b, "profiles", e =>
        {
            Fk<Profile, Participant>(e, x => x.ParticipantId);
            e.HasIndex(x => x.ParticipantId).IsUnique();
            Str(e, x => x.DisplayName, 100, required: false);
            Str(e, x => x.VoicePreference, 100, required: false);
            Str(e, x => x.FacePreference, 100, required: false);
            Str(e, x => x.Speed, 20);
        });
        Table<DemographicsForm>(b, "demographics_forms", e =>
        {
            Fk<DemographicsForm, Study>(e, x => x.StudyId);
            e.HasIndex(x => new { x.StudyId, x.Version }).IsUnique().HasDatabaseName("uq_form_version");
        });
        Table<DemographicsAnswer>(b, "demographics_answers", e =>
        {
            Fk<DemographicsAnswer, Participant>(e, x => x.ParticipantId);
            e.HasIndex(x => x.ParticipantId).IsUnique();
        });

        // ---------- step 2 ----------
        Table<MeasurementSettings>(b, "measurement_settings", e =>
        {
            Fk<MeasurementSettings, Study>(e, x => x.StudyId);
            e.HasIndex(x => x.StudyId).IsUnique();
            e.Property(x => x.Version).HasDefaultValue(1);
        });
        Table<Session>(b, "sessions", e =>
        {
            Fk<Session, Participant>(e, x => x.ParticipantId);
            Fk<Session, Study>(e, x => x.StudyId);
            Str(e, x => x.EndReason, 20, required: false);
        });
        Table<Calibration>(b, "calibrations", e => Fk<Calibration, Session>(e, x => x.SessionId));
        Table<Validation>(b, "validations", e =>
        {
            Fk<Validation, Session>(e, x => x.SessionId);
            Fk<Validation, Calibration>(e, x => x.CalibrationId);
        });
        Table<StimulusLayout>(b, "stimulus_layouts", e =>
        {
            Fk<StimulusLayout, Session>(e, x => x.SessionId);
            Str(e, x => x.Segment, 12);
        });
        Table<GazeSample>(b, "gaze_samples", e =>
        {
            Fk<GazeSample, Session>(e, x => x.SessionId);
            e.HasOne<StimulusLayout>().WithMany().HasForeignKey(x => x.LayoutId).OnDelete(DeleteBehavior.NoAction);
            Str(e, x => x.Region, 12);
            Str(e, x => x.Segment, 12);
            e.HasIndex(x => new { x.SessionId, x.TMs }).HasDatabaseName("ix_gaze_samples_session_t");
        });
        Table<SessionEvent>(b, "session_events", e =>
        {
            Fk<SessionEvent, Session>(e, x => x.SessionId);
            Str(e, x => x.Type, 24);
        });

        // ---------- step 3 ----------
        Table<Protocol>(b, "protocols", e =>
        {
            Fk<Protocol, Study>(e, x => x.StudyId);
            Str(e, x => x.Name, 200);
        });
        Table<ContentItem>(b, "content_items", e =>
        {
            Fk<ContentItem, Study>(e, x => x.StudyId);
            Str(e, x => x.Title, 200);
            Str(e, x => x.FaceId, 100);
            Str(e, x => x.VoiceId, 100);
        });
        Table<ContentMedia>(b, "content_media", e =>
        {
            Fk<ContentMedia, ContentItem>(e, x => x.ContentId);
            Str(e, x => x.Key, 120, exact: true);
            Str(e, x => x.Path, 500);
            Str(e, x => x.ContentType, 60);
            e.HasIndex(x => new { x.ContentId, x.Key }).IsUnique().HasDatabaseName("uq_media_key");
        });
        Table<Assignment>(b, "assignments", e =>
        {
            Fk<Assignment, Participant>(e, x => x.ParticipantId);
            Fk<Assignment, Study>(e, x => x.StudyId);
            Fk<Assignment, Protocol>(e, x => x.ProtocolId);
            e.HasOne<ContentItem>().WithMany().HasForeignKey(x => x.ContentId).OnDelete(DeleteBehavior.NoAction);
            Str(e, x => x.Topic, 200, required: false);
        });
        Table<Trial>(b, "trials", e =>
        {
            Fk<Trial, Session>(e, x => x.SessionId);
            Str(e, x => x.NumberShown, 20);
            Str(e, x => x.Zone, 20);
            Str(e, x => x.Response, 20, required: false);
        });
        Table<StageResult>(b, "stage_results", e =>
        {
            Fk<StageResult, Session>(e, x => x.SessionId);
            Str(e, x => x.Decision, 12);
            Str(e, x => x.Reason, 40);
        });
        Table<Answer>(b, "answers", e =>
        {
            Fk<Answer, Session>(e, x => x.SessionId);
            Str(e, x => x.SegmentId, 60);
            Str(e, x => x.QuestionId, 60);
            Str(e, x => x.Kind, 16);
            Str(e, x => x.Option, 200);
            Str(e, x => x.NextSegmentId, 60, required: false);
        });

        // ---------- step 4 ----------
        Table<AccessLogEntry>(b, "access_log", e =>
        {
            Str(e, x => x.Role, 20);
            Str(e, x => x.Action, 40);
            e.HasIndex(x => new { x.StudyId, x.CreatedAt }).HasDatabaseName("ix_access_log_study");
        });

        // ---------- step 5 ----------
        Table<AiBudget>(b, "ai_budgets", e =>
        {
            Fk<AiBudget, Study>(e, x => x.StudyId);
            e.HasIndex(x => x.StudyId).IsUnique();
        });
        Table<GenerationJob>(b, "generation_jobs", e =>
        {
            Fk<GenerationJob, Study>(e, x => x.StudyId);
            Fk<GenerationJob, ContentItem>(e, x => x.ContentId);
            Str(e, x => x.Kind, 10);
            Str(e, x => x.Provider, 40);
            Str(e, x => x.Status, 12);
            Str(e, x => x.SegmentId, 60, required: false);
            e.HasIndex(x => new { x.StudyId, x.Status }).HasDatabaseName("ix_generation_jobs_study_status");
        });

        // ---------- step 6 ----------
        Table<SettingsVersion>(b, "settings_versions", e =>
        {
            Fk<SettingsVersion, Study>(e, x => x.StudyId);
            e.HasIndex(x => new { x.StudyId, x.Version }).IsUnique().HasDatabaseName("uq_settings_versions_study_version");
        });
        Table<Observation>(b, "observations", e =>
        {
            Fk<Observation, Study>(e, x => x.StudyId);
            Fk<Observation, Session>(e, x => x.SessionId);
            Str(e, x => x.Category, 20);
            Str(e, x => x.Severity, 10);
            e.HasIndex(x => x.SessionId).HasDatabaseName("ix_observations_session");
        });
        Table<DebriefForm>(b, "debrief_forms", e =>
        {
            Fk<DebriefForm, Study>(e, x => x.StudyId);
            e.HasIndex(x => new { x.StudyId, x.Version }).IsUnique().HasDatabaseName("uq_debrief_forms_study_version");
        });
        Table<DebriefAnswer>(b, "debrief_answers", e =>
        {
            Fk<DebriefAnswer, Study>(e, x => x.StudyId);
            Fk<DebriefAnswer, Session>(e, x => x.SessionId);
            e.HasIndex(x => x.SessionId).IsUnique();
        });
        Table<ReferenceRecording>(b, "reference_recordings", e =>
        {
            Fk<ReferenceRecording, Study>(e, x => x.StudyId);
            Fk<ReferenceRecording, Session>(e, x => x.SessionId);
            Str(e, x => x.Source, 120);
        });
        Table<ReferenceSample>(b, "reference_samples", e =>
        {
            Fk<ReferenceSample, ReferenceRecording>(e, x => x.RecordingId);
            e.HasIndex(x => new { x.RecordingId, x.TMs }).HasDatabaseName("ix_reference_samples_recording_t");
        });

        // ---------- step 7 ----------
        Table<LiveConversation>(b, "live_conversations", e =>
        {
            Fk<LiveConversation, Session>(e, x => x.SessionId);
            Fk<LiveConversation, Study>(e, x => x.StudyId);
            e.HasIndex(x => x.SessionId).IsUnique();
            Str(e, x => x.Topic, 200);
            Str(e, x => x.InputMode, 10);
            Str(e, x => x.ReplyProvider, 40);
            Str(e, x => x.AvatarProvider, 40);
            Str(e, x => x.SttProvider, 40);
            Str(e, x => x.EndReason, 30, required: false);
        });
        Table<LiveTurn>(b, "live_turns", e =>
        {
            Fk<LiveTurn, LiveConversation>(e, x => x.ConversationId);
            Fk<LiveTurn, Session>(e, x => x.SessionId);
            Str(e, x => x.Role, 12);
            e.HasIndex(x => new { x.ConversationId, x.Index }).HasDatabaseName("ix_live_turns_conversation");
        });

        // snake_case column names everywhere; every string without an explicit length is nvarchar(max)
        foreach (var entity in b.Model.GetEntityTypes())
            foreach (var property in entity.GetProperties())
                property.SetColumnName(Wire.Name(property.Name));
    }

    private static void Table<T>(ModelBuilder b, string name, Action<EntityTypeBuilder<T>> configure) where T : class
    {
        var e = b.Entity<T>();
        e.ToTable(name);
        e.HasKey("Id");
        configure(e);
    }

    private static void Str<T>(EntityTypeBuilder<T> e, Expression<Func<T, string?>> property, int length, bool required = true, bool exact = false) where T : class
    {
        var p = e.Property(property).HasMaxLength(length).IsRequired(required);
        // SQL Server compares text case-insensitively by default; tokens, codes and keys must match exactly.
        if (exact)
            p.UseCollation("Latin1_General_100_BIN2");
    }

    private static void Fk<T, TPrincipal>(EntityTypeBuilder<T> e, Expression<Func<T, object?>> key) where T : class where TPrincipal : class =>
        e.HasOne<TPrincipal>().WithMany().HasForeignKey(key).OnDelete(DeleteBehavior.NoAction);
}
