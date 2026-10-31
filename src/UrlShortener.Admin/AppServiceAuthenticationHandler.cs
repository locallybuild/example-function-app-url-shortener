using System.Security.Claims;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace UrlShortener.Admin;

/// <summary>
/// Turns the user App Service Authentication signed in into the request's
/// <see cref="ClaimsPrincipal"/>.
///
/// App Service signs the user in before the request reaches the app, then
/// passes who they are in X-MS-CLIENT-PRINCIPAL: base64-encoded JSON holding
/// their claims, and which claim types carry their name and roles. App Service
/// removes any X-MS-CLIENT-PRINCIPAL a caller sends, so it can be trusted here,
/// behind App Service; the app shouldn't be reachable any other way.
/// </summary>
public sealed class AppServiceAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string SchemeName = "AppServiceAuthentication";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var header = Request.Headers["X-MS-CLIENT-PRINCIPAL"].ToString();
        if (string.IsNullOrEmpty(header))
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }

        ClientPrincipal? principal;
        try
        {
            principal = JsonSerializer.Deserialize<ClientPrincipal>(Encoding.UTF8.GetString(Convert.FromBase64String(header)));
        }
        catch (Exception ex) when (ex is FormatException or JsonException)
        {
            return Task.FromResult(AuthenticateResult.Fail("X-MS-CLIENT-PRINCIPAL isn't valid"));
        }
        if (principal is null)
        {
            return Task.FromResult(AuthenticateResult.Fail("X-MS-CLIENT-PRINCIPAL is empty"));
        }

        var identity = new ClaimsIdentity(
            principal.Claims.Select(c => new Claim(c.Type, c.Value)),
            principal.AuthenticationType,
            principal.NameClaimType ?? ClaimTypes.Name,
            principal.RoleClaimType ?? ClaimTypes.Role);

        // App Service sends each app role in a "roles" claim, whatever
        // role_typ says, so treat those as roles too.
        foreach (var role in principal.Claims.Where(c => c.Type == "roles"))
        {
            if (!identity.HasClaim(identity.RoleClaimType, role.Value))
            {
                identity.AddClaim(new Claim(identity.RoleClaimType, role.Value));
            }
        }

        return Task.FromResult(AuthenticateResult.Success(
            new AuthenticationTicket(new ClaimsPrincipal(identity), SchemeName)));
    }

    // Normally App Service has already sent anyone not signed in to sign in, so
    // this only happens if the app is reached some other way.
    protected override Task HandleChallengeAsync(AuthenticationProperties properties)
    {
        var returnTo = properties.RedirectUri ?? Request.Path.ToString();
        Response.Redirect($"/.auth/login/aad?post_login_redirect_uri={Uri.EscapeDataString(returnTo)}");
        return Task.CompletedTask;
    }

    protected override Task HandleForbiddenAsync(AuthenticationProperties properties)
    {
        Response.Redirect("/forbidden");
        return Task.CompletedTask;
    }

    private sealed record ClientPrincipal(
        [property: JsonPropertyName("auth_typ")] string AuthenticationType,
        [property: JsonPropertyName("name_typ")] string? NameClaimType,
        [property: JsonPropertyName("role_typ")] string? RoleClaimType,
        [property: JsonPropertyName("claims")] IReadOnlyList<ClientPrincipalClaim> Claims);

    private sealed record ClientPrincipalClaim(
        [property: JsonPropertyName("typ")] string Type,
        [property: JsonPropertyName("val")] string Value);
}
