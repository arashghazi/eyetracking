using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace EyeTracking.Infrastructure.Db;

/// <summary>Lets <c>dotnet ef migrations add</c> build the model without starting the app.
/// The connection string is never opened when adding a migration.</summary>
public sealed class DesignTimeDb : IDesignTimeDbContextFactory<EyeTrackingDb>
{
    public EyeTrackingDb CreateDbContext(string[] args) =>
        new(new DbContextOptionsBuilder<EyeTrackingDb>()
            .UseSqlServer("Server=localhost;Database=EyeTracking_Design;Trusted_Connection=True;TrustServerCertificate=True")
            .Options);
}
