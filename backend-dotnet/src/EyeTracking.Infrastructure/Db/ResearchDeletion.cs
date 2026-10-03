using EyeTracking.Domain;
using Microsoft.EntityFrameworkCore;

namespace EyeTracking.Infrastructure.Db;

/// <summary>Deletion rules of step 4 (purge_participant_research_data and delete_participant in
/// backend/eyetracking/infrastructure/uow.py). SQL Server enforces every foreign key and nothing
/// cascades, so children go before their parents: reference samples before recordings, pilot and
/// live rows, samples before layouts, validations before calibrations, everything under a session
/// before the session, sessions before assignments, and all of it before the participant row.
/// The deletes run in the request transaction (rolled back unless the use case commits); they do
/// not go through the change tracker, so pending changes are flushed first, as SQLAlchemy does.</summary>
public sealed partial class EfUnitOfWork
{
    public OrderedDictionary<string, int> PurgeParticipantResearchData(int participantId)
    {
        Flush();
        var sessionIds = _db.Set<Session>().Where(s => s.ParticipantId == participantId).Select(s => s.Id);
        var counts = new OrderedDictionary<string, int> { ["sessions"] = sessionIds.Count() };
        if (counts["sessions"] > 0)
        {
            var recordingIds = _db.Set<ReferenceRecording>().Where(r => sessionIds.Contains(r.SessionId)).Select(r => r.Id);
            counts["reference_samples"] = _db.Set<ReferenceSample>().Where(x => recordingIds.Contains(x.RecordingId)).ExecuteDelete();
            counts["reference_recordings"] = _db.Set<ReferenceRecording>().Where(x => sessionIds.Contains(x.SessionId)).ExecuteDelete();
            counts["observations"] = _db.Set<Observation>().Where(x => sessionIds.Contains(x.SessionId)).ExecuteDelete();
            counts["debrief_answers"] = _db.Set<DebriefAnswer>().Where(x => sessionIds.Contains(x.SessionId)).ExecuteDelete();
            counts["live_turns"] = _db.Set<LiveTurn>().Where(x => sessionIds.Contains(x.SessionId)).ExecuteDelete();
            counts["live_conversations"] = _db.Set<LiveConversation>().Where(x => sessionIds.Contains(x.SessionId)).ExecuteDelete();
            counts["samples"] = _db.Set<GazeSample>().Where(x => sessionIds.Contains(x.SessionId)).ExecuteDelete();
            counts["events"] = _db.Set<SessionEvent>().Where(x => sessionIds.Contains(x.SessionId)).ExecuteDelete();
            counts["trials"] = _db.Set<Trial>().Where(x => sessionIds.Contains(x.SessionId)).ExecuteDelete();
            counts["stage_results"] = _db.Set<StageResult>().Where(x => sessionIds.Contains(x.SessionId)).ExecuteDelete();
            counts["answers"] = _db.Set<Answer>().Where(x => sessionIds.Contains(x.SessionId)).ExecuteDelete();
            counts["validations"] = _db.Set<Validation>().Where(x => sessionIds.Contains(x.SessionId)).ExecuteDelete();
            counts["calibrations"] = _db.Set<Calibration>().Where(x => sessionIds.Contains(x.SessionId)).ExecuteDelete();
            counts["layouts"] = _db.Set<StimulusLayout>().Where(x => sessionIds.Contains(x.SessionId)).ExecuteDelete();
            _db.Set<Session>().Where(s => s.ParticipantId == participantId).ExecuteDelete();
        }
        else
        {
            foreach (var name in new[] { "samples", "events", "trials", "stage_results", "answers", "validations", "calibrations", "layouts",
                     "reference_samples", "reference_recordings", "observations", "debrief_answers", "live_turns", "live_conversations" })
                counts[name] = 0;
        }
        counts["consents"] = _db.Set<Consent>().Where(x => x.ParticipantId == participantId).ExecuteDelete();
        counts["demographics"] = _db.Set<DemographicsAnswer>().Where(x => x.ParticipantId == participantId).ExecuteDelete();
        counts["profile"] = _db.Set<Profile>().Where(x => x.ParticipantId == participantId).ExecuteDelete();
        counts["assignments"] = _db.Set<Assignment>().Where(x => x.ParticipantId == participantId).ExecuteDelete();
        return counts;
    }

    public void DeleteParticipant(int participantId)
    {
        Flush();
        _db.Set<Participant>().Where(p => p.Id == participantId).ExecuteDelete();
    }
}
