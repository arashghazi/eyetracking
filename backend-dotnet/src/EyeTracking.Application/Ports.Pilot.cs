using EyeTracking.Domain;

namespace EyeTracking.Application;

// Step 6 ports: the supervised pilot (PilotUnitOfWork in ports.py). Settings versions came with
// step 2; the debrief answer repository was started in step 4, whose raw-data download reads it.

public interface IObservationRepo
{
    Observation Add(Observation o);
    /// <summary>Oldest first.</summary>
    List<Observation> ForSession(int sessionId);
    /// <summary>Oldest first.</summary>
    List<Observation> ForStudy(int studyId);
}

public interface IDebriefFormRepo
{
    DebriefForm Add(DebriefForm f);
    /// <summary>The highest version, or null when the study never saved one.</summary>
    DebriefForm? Current(int studyId);
    DebriefForm? GetVersion(int studyId, int version);
}

public partial interface IDebriefAnswerRepo
{
    DebriefAnswer Add(DebriefAnswer a);
    /// <summary>Oldest first.</summary>
    List<DebriefAnswer> ForStudy(int studyId);
}

public interface IReferenceRepo
{
    /// <summary>Adds the recording and its rows (bulk insert; a tracker export can have millions).</summary>
    ReferenceRecording Add(ReferenceRecording r, IReadOnlyList<ReferenceRow> rows);
    ReferenceRecording? Get(int recordingId);
    /// <summary>Oldest first.</summary>
    List<ReferenceRecording> ForSession(int sessionId);
    /// <summary>Oldest first.</summary>
    List<ReferenceRecording> ForStudy(int studyId);
    /// <summary>Ordered by time.</summary>
    List<ReferenceRow> Samples(int recordingId);
}

public partial interface IUnitOfWork
{
    IObservationRepo Observations { get; }
    IDebriefFormRepo DebriefForms { get; }
    IReferenceRepo References { get; }
}
