using EyeTracking.Application;
using EyeTracking.Infrastructure;
using EyeTracking.Infrastructure.Db;
using EyeTracking.Web;
using EyeTracking.Web.Http;
using Microsoft.EntityFrameworkCore;

// Composition root: builds the API from settings (backend/eyetracking/web/app.py).

var settings = Settings.Load();
var builder = WebApplication.CreateBuilder(args);
builder.Logging.AddFilter("Microsoft.EntityFrameworkCore", LogLevel.Warning);

builder.Services.AddSingleton(settings);
builder.Services.AddDbContext<EyeTrackingDb>(o => o.UseSqlServer(settings.DbConnection, sql => sql.EnableRetryOnFailure(0)));
builder.Services.AddScoped<EfUnitOfWork>();
builder.Services.AddScoped<IUnitOfWork>(sp => sp.GetRequiredService<EfUnitOfWork>());
builder.Services.AddSingleton<IPasswordHasher, Argon2Hasher>();
builder.Services.AddSingleton<ITokenIssuer>(new JwtTokens(settings.JwtSecret, settings.JwtExpireMinutes));
builder.Services.AddSingleton<IClock, SystemClock>();
builder.Services.AddHttpClient();
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p
    .WithOrigins([.. settings.CorsOrigins])
    .AllowCredentials()
    .AllowAnyMethod()
    .AllowAnyHeader()));

var modules = EndpointModules.Discover();
foreach (var module in modules)
    module.AddServices(builder.Services, settings);

var app = builder.Build();

Startup.PrepareDatabase(app.Services, settings);

app.UseMiddleware<ErrorMiddleware>();
app.UseCors();

app.MapGet("/health", () => Reply.Ok(new { status = "ok" }));
foreach (var module in modules)
    module.Map(app);
app.MapFallback(() => Reply.Json(new { detail = "Not Found" }, 404));

app.Run();

/// <summary>Visible to the test project (WebApplicationFactory).</summary>
public partial class Program;
