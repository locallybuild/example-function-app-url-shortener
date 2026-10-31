using Azure.Core;
using Microsoft.ApplicationInsights.Extensibility;
using Microsoft.AspNetCore.Authentication;
using UrlShortener.Admin;
using UrlShortener.Data;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddLinkStore(builder.Configuration);

// Application Insights: requests, the PostgreSQL calls as dependencies, and the
// LinkCreated / LinkDeleted events from Pages/Index.cshtml.cs. The connection
// string comes from APPLICATIONINSIGHTS_CONNECTION_STRING.
builder.Services.AddApplicationInsightsTelemetry();

// Local authentication is disabled on the Application Insights resource, so
// each batch of telemetry carries an Entra access token for the app's managed
// identity.
builder.Services.AddOptions<TelemetryConfiguration>()
    .Configure<TokenCredential>((config, credential) => config.SetAzureTokenCredential(credential));

// App Service Authentication signs admins in (see 8-admin-app.tf), and the
// handler reads who they are from the header App Service passes. Every page
// needs the Admin app role (7-entra-application.tf), except the two a signed-in
// user without it, or a signed-out one, is sent to.
builder.Services.AddAuthentication(AppServiceAuthenticationHandler.SchemeName)
    .AddScheme<AuthenticationSchemeOptions, AppServiceAuthenticationHandler>(AppServiceAuthenticationHandler.SchemeName, null);

builder.Services.AddAuthorizationBuilder()
    .AddPolicy("Admin", policy => policy.RequireRole("Admin"));

builder.Services.AddRazorPages(options =>
{
    options.Conventions.AuthorizeFolder("/", "Admin");
    options.Conventions.AllowAnonymousToPage("/Forbidden");
    options.Conventions.AllowAnonymousToPage("/SignedOut");
});

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();

app.MapRazorPages();

// App Service's health check (health_check_path in 8-admin-app.tf).
app.MapGet("/healthz", () => Results.Ok("ok"));

app.Run();
