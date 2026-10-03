using EyeTracking.Domain;

namespace EyeTracking.Application;

// Step 2 ports: sessions and measurement (MeasurementUnitOfWork in ports.py).

public interface ISessionRepo
{
    Session Add(Session s);
    Session? Get(int sessionId);
    /// <summary>Newest first.</summary>
    List<Session> ListForParticipant(int participantId);
    /// <summary>Newest first.</summary>
    List<Session> ListForStudy(int studyId);
}

public interface ICalibrationRepo
{
    Calibration Add(Calibration c);
    Calibration? Latest(int sessionId);
}

public interface IValidationRepo
{
    Validation Add(Validation v);
    Validation? Latest(int sessionId);
}

public interface ILayoutRepo
{
    StimulusLayout Add(StimulusLayout l);
    StimulusLayout? Latest(int sessionId);
    List<StimulusLayout> SessionAll(int sessionId);
}

public interface ISampleRepo
{
    int AddMany(IReadOnlyCollection<GazeSample> samples);
    /// <summary>Ordered by time, then id.</summary>
    List<GazeSample> ForSession(int sessionId);
    (int Total, List<GazeSample> Items) Page(int sessionId, int offset, int limit);
}

public interface IEventRepo
{
    SessionEvent Add(SessionEvent e);
    /// <summary>Ordered by time, then id.</summary>
    List<SessionEvent> ForSession(int sessionId);
}

public interface IMeasurementSettingsRepo
{
    MeasurementSettings? Get(int studyId);
    MeasurementSettings Save(MeasurementSettings s);
}

public interface ISettingsVersionRepo
{
    SettingsVersion Add(SettingsVersion v);
    /// <summary>Oldest version first.</summary>
    List<SettingsVersion> ListForStudy(int studyId);
}

public partial interface IUnitOfWork
{
    ISettingsVersionRepo SettingsVersions { get; }
    ISessionRepo Sessions { get; }
    ICalibrationRepo Calibrations { get; }
    IValidationRepo Validations { get; }
    ILayoutRepo Layouts { get; }
    ISampleRepo Samples { get; }
    IEventRepo Events { get; }
    IMeasurementSettingsRepo MeasurementSettings { get; }
}
