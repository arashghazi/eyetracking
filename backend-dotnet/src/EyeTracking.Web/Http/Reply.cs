using System.Text.Json.Nodes;
using EyeTracking.Domain;

namespace EyeTracking.Web.Http;

/// <summary>JSON responses in the Python service's wire format (see JsonFormat).</summary>
public static class Reply
{
    public static IResult Json(object? value, int status = 200) =>
        value is JsonNode node
            ? Results.Text(node.ToJsonString(JsonFormat.Options), "application/json", statusCode: status)
            : Results.Json(value, JsonFormat.Options, "application/json", status);

    public static IResult Ok(object? value) => Json(value);

    public static IResult Created(object? value) => Json(value, 201);
}
