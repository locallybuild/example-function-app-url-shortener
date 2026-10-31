using System.Net;
using Microsoft.ApplicationInsights;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using UrlShortener.Data;

namespace UrlShortener.Functions;

public sealed class Redirect(LinkStore links, TelemetryClient telemetry)
{
    /// <summary>
    /// GET /{code} - redirects to the link's target and counts the click.
    ///
    /// Each redirect is also recorded in Application Insights as a
    /// LinkFollowed event (or LinkNotFound), with the code, the target, and
    /// where the visitor came from.
    /// </summary>
    [Function("Redirect")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "{code}")] HttpRequestData request,
        string code)
    {
        var target = await links.FollowAsync(code, request.FunctionContext.CancellationToken);

        var properties = new Dictionary<string, string>
        {
            ["code"] = code,
            ["referrer"] = Header(request, "Referer"),
            ["userAgent"] = Header(request, "User-Agent"),
        };

        if (target is null)
        {
            telemetry.TrackEvent("LinkNotFound", properties);

            var notFound = request.CreateResponse(HttpStatusCode.NotFound);
            await notFound.WriteStringAsync($"No link with the code '{code}'.");
            return notFound;
        }

        properties["targetUrl"] = target;
        telemetry.TrackEvent("LinkFollowed", properties);

        // 302 rather than 301: browsers cache a 301 forever, so later clicks
        // wouldn't reach the app to be counted, and a removed link would keep
        // working for anyone who had followed it.
        var response = request.CreateResponse(HttpStatusCode.Found);
        response.Headers.Add("Location", target);
        response.Headers.Add("Cache-Control", "no-store");
        return response;
    }

    private static string Header(HttpRequestData request, string name) =>
        request.Headers.TryGetValues(name, out var values) ? string.Join(",", values) : "";
}
