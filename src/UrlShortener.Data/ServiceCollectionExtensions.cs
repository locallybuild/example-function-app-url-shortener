using Azure.Core;
using Azure.Identity;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace UrlShortener.Data;

public static class ServiceCollectionExtensions
{
    // The scope Azure Database for PostgreSQL accepts Entra access tokens for.
    private const string PostgresTokenScope = "https://ossrdbms-aad.database.windows.net/.default";

    /// <summary>
    /// Registers the app's managed identity as a <see cref="TokenCredential"/>,
    /// and a <see cref="LinkStore"/> that connects to PostgreSQL as it.
    ///
    /// Configuration comes from the app settings in locals.tf: PGHOST, PGPORT,
    /// PGDATABASE, PGUSER and AZURE_CLIENT_ID. PG_CA_CERT is optional.
    /// </summary>
    public static IServiceCollection AddLinkStore(this IServiceCollection services, IConfiguration configuration)
    {
        // AZURE_CLIENT_ID selects the user-assigned identity attached to the
        // app, which is also the PostgreSQL server's Entra administrator and
        // holds the role for sending telemetry.
        var credential = new ManagedIdentityCredential(
            ManagedIdentityId.FromUserAssignedClientId(Required(configuration, "AZURE_CLIENT_ID")));
        services.AddSingleton<TokenCredential>(credential);

        var connection = new NpgsqlConnectionStringBuilder
        {
            Host = Required(configuration, "PGHOST"),
            // Locally serves PostgreSQL on a non-standard port; Azure uses 5432.
            Port = int.Parse(configuration["PGPORT"] ?? "5432"),
            Database = Required(configuration, "PGDATABASE"),
            Username = Required(configuration, "PGUSER"),
            // Locally serves PostgreSQL over TLS (as Azure does), so always
            // connect over TLS. If a CA certificate is supplied (PG_CA_CERT),
            // the server certificate is verified against it - do this against
            // Azure, pointing at the DigiCert Global Root. Locally's emulator
            // uses a certificate that isn't in the app's trust store, so with no
            // CA supplied verification is skipped: the connection is still
            // encrypted, but the server isn't authenticated.
            SslMode = configuration["PG_CA_CERT"] is null ? SslMode.Require : SslMode.VerifyFull,
            RootCertificate = configuration["PG_CA_CERT"],
        };

        var builder = new NpgsqlDataSourceBuilder(connection.ConnectionString);

        // There's no database password: the managed identity's Entra access
        // token IS the password. Tokens expire (typically after an hour), so
        // the data source fetches a fresh one well before then, and new
        // connections always present a current token.
        builder.UsePeriodicPasswordProvider(
            async (_, cancellationToken) =>
                (await credential.GetTokenAsync(new TokenRequestContext([PostgresTokenScope]), cancellationToken)).Token,
            successRefreshInterval: TimeSpan.FromMinutes(30),
            failureRefreshInterval: TimeSpan.FromSeconds(10));

        services.AddSingleton(builder.Build());
        services.AddSingleton<LinkStore>();
        return services;
    }

    private static string Required(IConfiguration configuration, string name) =>
        configuration[name] is { Length: > 0 } value
            ? value
            : throw new InvalidOperationException($"the setting {name} must be set");
}
