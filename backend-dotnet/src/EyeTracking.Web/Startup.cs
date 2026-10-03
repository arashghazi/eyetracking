using EyeTracking.Application;
using EyeTracking.Infrastructure.Db;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace EyeTracking.Web;

public static class Startup
{
    /// <summary>Creates the schema when the database is new and makes sure the first admin exists.</summary>
    public static void PrepareDatabase(IServiceProvider services, Settings settings)
    {
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<EyeTrackingDb>();
        if (db.Database.GetMigrations().Any())
            db.Database.Migrate();
        else
            db.Database.EnsureCreated();
        BootstrapAdmin(scope.ServiceProvider, settings);
    }

    public static void BootstrapAdmin(IServiceProvider services, Settings settings)
    {
        if (string.IsNullOrEmpty(settings.BootstrapAdminEmail) || string.IsNullOrEmpty(settings.BootstrapAdminPassword))
            return;
        var uow = services.GetRequiredService<IUnitOfWork>();
        UseCases.BootstrapAdmin(uow, services.GetRequiredService<IPasswordHasher>(), settings.BootstrapAdminEmail, settings.BootstrapAdminPassword);
    }

    public static string DatabaseName(Settings settings) => new SqlConnectionStringBuilder(settings.DbConnection).InitialCatalog;
}
