namespace EyeTracking.Web.Http;

/// <summary>One group of endpoints, usually one Python router. Every non-abstract class that
/// implements this interface is found at startup: <see cref="AddServices"/> registers what the
/// module needs and <see cref="Map"/> adds its routes. Add a module in its own file; there is
/// no central list to edit.</summary>
public interface IEndpointModule
{
    void AddServices(IServiceCollection services, Settings settings) { }

    void Map(IEndpointRouteBuilder app);
}

public static class EndpointModules
{
    public static IReadOnlyList<IEndpointModule> Discover() =>
        typeof(IEndpointModule).Assembly.GetTypes()
            .Where(t => t is { IsClass: true, IsAbstract: false } && typeof(IEndpointModule).IsAssignableFrom(t))
            .OrderBy(t => t.FullName, StringComparer.Ordinal)
            .Select(t => (IEndpointModule)Activator.CreateInstance(t)!)
            .ToList();
}
