using EyeTracking.Application;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace EyeTracking.Infrastructure.Db;

/// <summary>One request, one unit of work. A repository Add saves at once inside an open
/// transaction (so ids exist, like a SQLAlchemy flush); Commit makes it permanent, and
/// disposing without Commit rolls everything back. Each build step adds its repositories
/// to this partial class in its own file.</summary>
public sealed partial class EfUnitOfWork : IUnitOfWork
{
    private readonly EyeTrackingDb _db;
    private IDbContextTransaction? _tx;

    public EfUnitOfWork(EyeTrackingDb db)
    {
        _db = db;
        Users = new UserRepo(this);
        Studies = new StudyRepo(this);
        Memberships = new MembershipRepo(this);
        Participants = new ParticipantRepo(this);
        Invitations = new InvitationRepo(this);
        Sheets = new SheetRepo(this);
        Consents = new ConsentRepo(this);
        Profiles = new ProfileRepo(this);
        Demographics = new DemographicsRepo(this);
        AccessLog = new AccessLogRepo(this);
    }

    public EyeTrackingDb Db => _db;

    public IUserRepo Users { get; }
    public IStudyRepo Studies { get; }
    public IMembershipRepo Memberships { get; }
    public IParticipantRepo Participants { get; }
    public IInvitationRepo Invitations { get; }
    public ISheetRepo Sheets { get; }
    public IConsentRepo Consents { get; }
    public IProfileRepo Profiles { get; }
    public IDemographicsRepo Demographics { get; }
    public IAccessLogRepo AccessLog { get; }

    /// <summary>Writes pending changes inside the request's transaction (SQLAlchemy's flush).</summary>
    public void Flush()
    {
        _tx ??= _db.Database.BeginTransaction();
        _db.SaveChanges();
    }

    /// <summary>Adds and flushes, so the entity has its id.</summary>
    public T Add<T>(T entity) where T : class
    {
        _db.Add(entity);
        Flush();
        return entity;
    }

    /// <summary>Inserts a new entity or saves changes to a tracked one.</summary>
    public T Save<T>(T entity) where T : class
    {
        if (_db.Entry(entity).State == EntityState.Detached)
            _db.Add(entity);
        Flush();
        return entity;
    }

    public void Commit()
    {
        _db.SaveChanges();
        _tx?.Commit();
        _tx?.Dispose();
        _tx = null;
    }

    public void Rollback()
    {
        _tx?.Rollback();
        _tx?.Dispose();
        _tx = null;
        _db.ChangeTracker.Clear();
    }

    public void Dispose()
    {
        _tx?.Dispose();
        _tx = null;
    }
}
