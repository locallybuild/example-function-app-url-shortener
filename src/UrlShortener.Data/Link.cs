namespace UrlShortener.Data;

/// <summary>A short link: GET /{Code} on the Function App redirects to TargetUrl.</summary>
public sealed record Link(
    string Code,
    string TargetUrl,
    DateTimeOffset CreatedAt,
    long Clicks,
    DateTimeOffset? LastClickedAt);
