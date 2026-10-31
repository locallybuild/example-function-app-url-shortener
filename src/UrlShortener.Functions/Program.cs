using Azure.Core;
using Microsoft.ApplicationInsights.Extensibility;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using UrlShortener.Data;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices((context, services) =>
    {
        services.AddLinkStore(context.Configuration);

        // Application Insights for the worker: requests, the PostgreSQL calls as
        // dependencies, and the custom events in Redirect.cs. The connection
        // string comes from APPLICATIONINSIGHTS_CONNECTION_STRING.
        services.AddApplicationInsightsTelemetryWorkerService();
        services.ConfigureFunctionsApplicationInsights();

        // Local authentication is disabled on the Application Insights
        // resource, so each batch of telemetry carries an Entra access token
        // for the app's managed identity.
        services.AddOptions<TelemetryConfiguration>()
            .Configure<TokenCredential>((config, credential) => config.SetAzureTokenCredential(credential));
    })
    .Build();

host.Run();
