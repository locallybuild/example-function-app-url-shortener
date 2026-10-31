using Microsoft.ApplicationInsights;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using UrlShortener.Data;

namespace UrlShortener.Admin.Pages;

public sealed class IndexModel(LinkStore links, TelemetryClient telemetry, IConfiguration configuration) : PageModel
{
    public IReadOnlyList<Link> Links { get; private set; } = [];

    public string ShortLinkBaseUrl { get; } = (configuration["SHORT_LINK_BASE_URL"] ?? "").TrimEnd('/');

    [BindProperty]
    public string? Code { get; set; }

    [BindProperty]
    public string TargetUrl { get; set; } = "";

    public string? Error { get; private set; }

    [TempData]
    public string? Notice { get; set; }

    public async Task OnGetAsync(CancellationToken cancellationToken)
    {
        Links = await links.ListAsync(cancellationToken);
    }

    public async Task<IActionResult> OnPostAddAsync(CancellationToken cancellationToken)
    {
        try
        {
            var link = await links.AddAsync(Code, TargetUrl, cancellationToken);
            telemetry.TrackEvent("LinkCreated", new Dictionary<string, string>
            {
                ["code"] = link.Code,
                ["targetUrl"] = link.TargetUrl,
                ["user"] = User.Identity?.Name ?? "",
            });

            Notice = $"Added {ShortLinkBaseUrl}/{link.Code}";
            return RedirectToPage();
        }
        catch (LinkValidationException ex)
        {
            // Show the form again with what was typed, and why it was refused.
            Error = ex.Message;
            Links = await links.ListAsync(cancellationToken);
            return Page();
        }
    }

    public async Task<IActionResult> OnPostDeleteAsync(string code, CancellationToken cancellationToken)
    {
        if (await links.DeleteAsync(code, cancellationToken))
        {
            telemetry.TrackEvent("LinkDeleted", new Dictionary<string, string>
            {
                ["code"] = code,
                ["user"] = User.Identity?.Name ?? "",
            });
            Notice = $"Removed {ShortLinkBaseUrl}/{code}";
        }
        return RedirectToPage();
    }
}
