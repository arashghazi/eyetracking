using System.Text.Json.Nodes;
using EyeTracking.Domain;

namespace EyeTracking.Application;

// Step 7 ports: the live avatar (LiveRepo, ReplyGenerator, SpeechToText and LiveAvatarProvider in
// ports.py). The reads research needs (ConversationForSession, Turns) came with step 4 in
// Ports.Research.cs. Providers describe themselves with info() dicts, kept as JSON.

public partial interface ILiveRepo
{
    LiveConversation AddConversation(LiveConversation c);
    LiveTurn AddTurn(LiveTurn t);
    List<LiveConversation> OpenForStudy(int studyId);
}

/// <summary>Writes the avatar's next reply as a dict matching <see cref="LiveRules.ReplySchema"/>.</summary>
public interface IReplyGenerator
{
    /// <summary><c>name</c>, <c>model</c>, <c>configured</c>, <c>synthetic</c> (and <c>effort</c>).</summary>
    JsonObject Info();
    double EstimateCost();
    /// <summary>The reply (null when the model answered JSON null; the guard rules then use a scripted
    /// line) and a meta dict (<c>cost_actual_units</c>, <c>model</c>). Raises <see cref="ReplyRefused"/>
    /// or <see cref="ReplyError"/> when there is no usable reply.</summary>
    Task<(JsonObject? Data, JsonObject Meta)> Reply(string system, string conversation, string topic);
}

/// <summary>Turns one recorded utterance into text. Audio is processed in memory and never stored.</summary>
public interface ISpeechToText
{
    /// <summary><c>name</c>, <c>configured</c>, <c>synthetic</c> (and <c>model</c>, <c>base_url</c>).</summary>
    JsonObject Info();
    /// <summary>Raises <see cref="SpeechError"/> when the audio cannot be turned into text.</summary>
    Task<string> Transcribe(byte[] audio, string contentType, string language = "en");
}

/// <summary>The face and voice the participant sees and hears.</summary>
public interface ILiveAvatarProvider
{
    JsonObject Info();
    JsonObject ClientConfig(string avatarId, string voiceId);
    double EstimateCostPerMinute();
}
