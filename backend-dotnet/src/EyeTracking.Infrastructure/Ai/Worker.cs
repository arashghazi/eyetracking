using System.Text.Json.Nodes;
using EyeTracking.Application;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace EyeTracking.Infrastructure.Ai;

/// <summary>Background job runner (backend/eyetracking/infrastructure/ai/worker.py): one loop, its
/// own unit of work per pass, stops on shutdown. Registered as a hosted service only when
/// EYETRACKING_AI_WORKER_ENABLED is set; <see cref="RunOnce"/> is usable on its own (tests).
/// Like the Python thread, stopping does not cancel a generation already in progress.</summary>
public sealed class AiWorker(IServiceScopeFactory scopes, AiProviders providers, IMediaStore store, IClock clock, ILogger<AiWorker> log, int intervalS = 5)
    : BackgroundService
{
    private readonly TimeSpan _interval = TimeSpan.FromSeconds(Math.Max(1, intervalS));

    public async Task<JsonObject> RunOnce(int maxJobs = 5)
    {
        using var scope = scopes.CreateScope();
        var uow = scope.ServiceProvider.GetRequiredService<IUnitOfWork>();
        return await AiUseCases.RunJobs(uow, providers, store, clock, maxJobs);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // a pass runs mostly synchronously; leave the host's startup first
        await Task.Yield();
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await RunOnce();
            }
            catch (Exception e)
            {
                log.LogError(e, "ai worker pass failed");
            }
            try
            {
                await Task.Delay(_interval, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }
}
