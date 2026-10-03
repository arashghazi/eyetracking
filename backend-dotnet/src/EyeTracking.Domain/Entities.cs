using System.Text.Json.Nodes;

namespace EyeTracking.Domain;

// Persistent entities of build steps 2-7. Each class is partial: the rules of a step live in
// that step's own file (Measurement.cs, Practice.cs, ...), ported from backend/eyetracking/domain.
// Property names are the Python field names in PascalCase; the database columns are snake_case.

// ---------- step 2: sessions and measurement ----------

public enum SessionStatus { Created, CameraOk, Calibrated, Validated, Running, Paused, Ended }

public partial class MeasurementSettings
{
    public int Id { get; set; }
    public int StudyId { get; set; }
    public double ValidationMinCorrect { get; set; } = 0.8;
    public double ValidationMaxUncertain { get; set; } = 0.2;
    public double MinRegionToErrorRatio { get; set; } = 2.0;
    public double GazeConfThreshold { get; set; } = 0.5;
    public int CalibrationPoints { get; set; } = 9;
    public bool AllowContinueWithoutValidation { get; set; } = true;
    public double QualityMaxUncertainShare { get; set; } = 0.2;
    public double QualityMaxMissingShare { get; set; } = 0.2;
    public int Version { get; set; } = 1;
}

public partial class Session
{
    public int Id { get; set; }
    public int ParticipantId { get; set; }
    public int StudyId { get; set; }
    public JsonObject Device { get; set; } = [];
    public JsonObject Screen { get; set; } = [];
    public JsonObject Camera { get; set; } = [];
    public JsonObject GazeModel { get; set; } = [];
    public bool Synthetic { get; set; } = true;
    public SessionStatus Status { get; set; } = SessionStatus.Created;
    public bool CalibrationValid { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? EndedAt { get; set; }
    public string? EndReason { get; set; }
    public List<string> Notes { get; set; } = [];
    public int? AssignmentId { get; set; }
    public int? ProtocolId { get; set; }
}

public partial class Calibration
{
    public int Id { get; set; }
    public int SessionId { get; set; }
    public JsonObject Params { get; set; } = [];
    public double ResidualPxMedian { get; set; }
    public double ResidualPxP90 { get; set; }
    public JsonArray PerTarget { get; set; } = [];
    public int Points { get; set; }
    public bool Accepted { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public partial class Validation
{
    public int Id { get; set; }
    public int SessionId { get; set; }
    public int CalibrationId { get; set; }
    public JsonObject Layout { get; set; } = [];
    public bool Passed { get; set; }
    public double CorrectRatio { get; set; }
    public double UncertainRatio { get; set; }
    public double SizeRatio { get; set; }
    public List<string> Reasons { get; set; } = [];
    public JsonArray Targets { get; set; } = [];
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public int? SettingsVersion { get; set; }
}

public partial class StimulusLayout
{
    public int Id { get; set; }
    public int SessionId { get; set; }
    public string Segment { get; set; } = "";
    public JsonObject Layout { get; set; } = [];
    public int? StageIndex { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public partial class GazeSample
{
    public int Id { get; set; }
    public int SessionId { get; set; }
    public int TMs { get; set; }
    public double? X { get; set; }
    public double? Y { get; set; }
    public double Conf { get; set; }
    public bool Valid { get; set; }
    public string Region { get; set; } = "";
    public string Segment { get; set; } = "";
    public int? LayoutId { get; set; }
}

public partial class SessionEvent
{
    public int Id { get; set; }
    public int SessionId { get; set; }
    public int TMs { get; set; }
    public string Type { get; set; } = "";
    public JsonObject Payload { get; set; } = [];
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

// ---------- step 3: practice ----------

public enum ProtocolStatus { Draft, Published }

public enum ContentStatus { Draft, Approved }

public enum AssignmentStatus { PendingTopic, ContentPending, Ready, InProgress, Completed, Cancelled }

public partial class Protocol
{
    public int Id { get; set; }
    public int StudyId { get; set; }
    public string Name { get; set; } = "";
    public JsonObject Definition { get; set; } = [];
    public ProtocolStatus Status { get; set; } = ProtocolStatus.Draft;
    public int Version { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? PublishedAt { get; set; }
}

public partial class ContentItem
{
    public int Id { get; set; }
    public int StudyId { get; set; }
    public string Title { get; set; } = "";
    public JsonObject Definition { get; set; } = [];
    public List<string> TopicTags { get; set; } = [];
    public string FaceId { get; set; } = "";
    public string VoiceId { get; set; } = "";
    public ContentStatus Status { get; set; } = ContentStatus.Draft;
    public bool TextReviewed { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

public partial class ContentMedia
{
    public int Id { get; set; }
    public int ContentId { get; set; }
    public string Key { get; set; } = "";
    public string Path { get; set; } = "";
    public string ContentType { get; set; } = "";
    public int Size { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public partial class Assignment
{
    public int Id { get; set; }
    public int ParticipantId { get; set; }
    public int StudyId { get; set; }
    public int ProtocolId { get; set; }
    public int OrderIndex { get; set; }
    public AssignmentStatus Status { get; set; } = AssignmentStatus.Ready;
    public string? Topic { get; set; }
    public string? TopicFreeText { get; set; }
    public int? ContentId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public partial class Trial
{
    public int Id { get; set; }
    public int SessionId { get; set; }
    public int StageIndex { get; set; }
    public int TrialIndex { get; set; }
    public int TMs { get; set; }
    public string NumberShown { get; set; } = "";
    public string Zone { get; set; } = "";
    public JsonObject Position { get; set; } = [];
    public int FaceLevel { get; set; }
    public string? Response { get; set; }
    public bool Correct { get; set; }
    public int? ResponseMs { get; set; }
}

public partial class StageResult
{
    public int Id { get; set; }
    public int SessionId { get; set; }
    public int StageIndex { get; set; }
    public string Decision { get; set; } = "";
    public string Reason { get; set; } = "";
    public double? CorrectRatio { get; set; }
    public double InvalidShare { get; set; }
    public int? ComfortValue { get; set; }
    public int Trials { get; set; }
    public int? NextStageIndex { get; set; }
    public int LastTrialId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public partial class Answer
{
    public int Id { get; set; }
    public int SessionId { get; set; }
    public string SegmentId { get; set; } = "";
    public string QuestionId { get; set; } = "";
    public string Kind { get; set; } = "";
    public string Option { get; set; } = "";
    public bool? Correct { get; set; }
    public int TMs { get; set; }
    public string? NextSegmentId { get; set; }
}

// ---------- step 4: research data ----------

public partial class AccessLogEntry
{
    public int Id { get; set; }
    public int? StudyId { get; set; }
    public int UserId { get; set; }
    public string Role { get; set; } = "";
    public string Action { get; set; } = "";
    public JsonObject Detail { get; set; } = [];
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

// ---------- step 5: AI content ----------

public partial class AiBudget
{
    public int Id { get; set; }
    public int StudyId { get; set; }
    public double CostCapUnits { get; set; }
    public double SpentUnits { get; set; }
    public bool SendFreeText { get; set; }
}

public partial class GenerationJob
{
    public int Id { get; set; }
    public int StudyId { get; set; }
    public string Kind { get; set; } = "";
    public string Provider { get; set; } = "";
    public int ContentId { get; set; }
    public string Status { get; set; } = "queued";
    public int? AssignmentId { get; set; }
    public string? SegmentId { get; set; }
    public int Attempts { get; set; }
    public int MaxAttempts { get; set; } = 3;
    public double CostEstimateUnits { get; set; }
    public double CostActualUnits { get; set; }
    public string? Error { get; set; }
    public JsonObject Request { get; set; } = [];
    public JsonObject Result { get; set; } = [];
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? StartedAt { get; set; }
    public DateTime? FinishedAt { get; set; }
    public DateTime? NextAttemptAt { get; set; }
}

// ---------- step 6: pilot ----------

public partial class SettingsVersion
{
    public int Id { get; set; }
    public int StudyId { get; set; }
    public int Version { get; set; }
    public JsonObject Values { get; set; } = [];
    public string Rationale { get; set; } = "";
    public int? ChangedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public partial class Observation
{
    public int Id { get; set; }
    public int StudyId { get; set; }
    public int SessionId { get; set; }
    public int AuthorId { get; set; }
    public string Category { get; set; } = "";
    public string Severity { get; set; } = "";
    public string Text { get; set; } = "";
    public int? TMs { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public partial class DebriefForm
{
    public int Id { get; set; }
    public int StudyId { get; set; }
    public int Version { get; set; }
    public JsonArray Questions { get; set; } = [];
    public bool Enabled { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public partial class DebriefAnswer
{
    public int Id { get; set; }
    public int StudyId { get; set; }
    public int SessionId { get; set; }
    public int ParticipantId { get; set; }
    public int FormVersion { get; set; }
    public JsonObject Answers { get; set; } = [];
    public bool Skipped { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public partial class ReferenceRecording
{
    public int Id { get; set; }
    public int StudyId { get; set; }
    public int SessionId { get; set; }
    public string Source { get; set; } = "";
    public int UploadedBy { get; set; }
    public JsonObject Settings { get; set; } = [];
    public int SampleCount { get; set; }
    public int ValidCount { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public partial class ReferenceSample
{
    public int Id { get; set; }
    public int RecordingId { get; set; }
    public int TMs { get; set; }
    public double? X { get; set; }
    public double? Y { get; set; }
    public bool Valid { get; set; }
}

// ---------- step 7: live avatar ----------

public enum ConversationStatus { Open, Closed }

public partial class LiveConversation
{
    public int Id { get; set; }
    public int SessionId { get; set; }
    public int StudyId { get; set; }
    public int ParticipantId { get; set; }
    public string Topic { get; set; } = "";
    public string InputMode { get; set; } = "";
    public bool TranscriptAllowed { get; set; }
    public string ReplyProvider { get; set; } = "";
    public string AvatarProvider { get; set; } = "";
    public string SttProvider { get; set; } = "";
    public ConversationStatus Status { get; set; } = ConversationStatus.Open;
    public int TurnsUsed { get; set; }
    public int OffTopicStreak { get; set; }
    public string? EndReason { get; set; }
    public double CostUnits { get; set; }
    public DateTime StartedAt { get; set; } = DateTime.UtcNow;
    public DateTime? EndedAt { get; set; }
}

public partial class LiveTurn
{
    public int Id { get; set; }
    public int ConversationId { get; set; }
    public int SessionId { get; set; }
    public int Index { get; set; }
    public string Role { get; set; } = "";
    public string? Text { get; set; }
    public int Chars { get; set; }
    public int? TMs { get; set; }
    public List<string> Flags { get; set; } = [];
    public int? LatencyMs { get; set; }
    public double CostUnits { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
