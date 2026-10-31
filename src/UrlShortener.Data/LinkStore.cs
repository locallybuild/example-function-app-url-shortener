using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Npgsql;

namespace UrlShortener.Data;

/// <summary>
/// The links table in PostgreSQL, shared by the Function App (which resolves
/// codes and counts clicks) and the admin site (which adds and removes links).
/// </summary>
public sealed partial class LinkStore(NpgsqlDataSource dataSource)
{
    private const string CodeAlphabet = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private const int GeneratedCodeLength = 7;

    // The Functions host owns these paths when the route prefix is empty, so a
    // link can't use them.
    private static readonly HashSet<string> ReservedCodes = new(StringComparer.OrdinalIgnoreCase) { "admin", "api", "runtime" };

    private readonly SemaphoreSlim _schemaLock = new(1, 1);
    private bool _schemaReady;

    [GeneratedRegex("^[A-Za-z0-9_-]{1,64}$")]
    private static partial Regex CodePattern();

    public async Task<IReadOnlyList<Link>> ListAsync(CancellationToken cancellationToken = default)
    {
        await EnsureSchemaAsync(cancellationToken);

        await using var command = dataSource.CreateCommand(
            "SELECT code, target_url, created_at, clicks, last_clicked_at FROM links ORDER BY created_at DESC");
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        var links = new List<Link>();
        while (await reader.ReadAsync(cancellationToken))
        {
            links.Add(new Link(
                reader.GetString(0),
                reader.GetString(1),
                reader.GetFieldValue<DateTimeOffset>(2),
                reader.GetInt64(3),
                reader.IsDBNull(4) ? null : reader.GetFieldValue<DateTimeOffset>(4)));
        }
        return links;
    }

    /// <summary>
    /// Adds a link. When <paramref name="code"/> is empty a random one is
    /// generated. Throws <see cref="LinkValidationException"/> if the code or
    /// URL isn't acceptable, or the code is taken.
    /// </summary>
    public async Task<Link> AddAsync(string? code, string targetUrl, CancellationToken cancellationToken = default)
    {
        if (!Uri.TryCreate(targetUrl?.Trim(), UriKind.Absolute, out var target) ||
            (target.Scheme != Uri.UriSchemeHttp && target.Scheme != Uri.UriSchemeHttps))
        {
            throw new LinkValidationException("The target must be an absolute http:// or https:// URL.");
        }

        code = code?.Trim();
        if (string.IsNullOrEmpty(code))
        {
            code = GenerateCode();
        }
        else if (!CodePattern().IsMatch(code))
        {
            throw new LinkValidationException("A code is 1-64 letters, digits, '-' or '_'.");
        }
        if (ReservedCodes.Contains(code))
        {
            throw new LinkValidationException($"'{code}' is reserved.");
        }

        await EnsureSchemaAsync(cancellationToken);

        await using var command = dataSource.CreateCommand(
            "INSERT INTO links (code, target_url) VALUES ($1, $2) ON CONFLICT (code) DO NOTHING RETURNING created_at");
        command.Parameters.AddWithValue(code);
        command.Parameters.AddWithValue(target.AbsoluteUri);

        var createdAt = await command.ExecuteScalarAsync(cancellationToken);
        if (createdAt is null)
        {
            throw new LinkValidationException($"The code '{code}' is already in use.");
        }
        return new Link(code, target.AbsoluteUri, (DateTimeOffset)(DateTime)createdAt, 0, null);
    }

    /// <summary>Removes a link. Returns false if there was no link with that code.</summary>
    public async Task<bool> DeleteAsync(string code, CancellationToken cancellationToken = default)
    {
        await EnsureSchemaAsync(cancellationToken);

        await using var command = dataSource.CreateCommand("DELETE FROM links WHERE code = $1");
        command.Parameters.AddWithValue(code);
        return await command.ExecuteNonQueryAsync(cancellationToken) > 0;
    }

    /// <summary>
    /// Looks a code up and counts the click in one statement. Returns the
    /// target URL, or null if there's no link with that code.
    /// </summary>
    public async Task<string?> FollowAsync(string code, CancellationToken cancellationToken = default)
    {
        await EnsureSchemaAsync(cancellationToken);

        await using var command = dataSource.CreateCommand(
            "UPDATE links SET clicks = clicks + 1, last_clicked_at = now() WHERE code = $1 RETURNING target_url");
        command.Parameters.AddWithValue(code);
        return (string?)await command.ExecuteScalarAsync(cancellationToken);
    }

    // Both apps create the table if it isn't there yet, so neither has to be
    // deployed first. A failure (say, the server is still starting) isn't
    // remembered; the next call tries again.
    private async Task EnsureSchemaAsync(CancellationToken cancellationToken)
    {
        if (_schemaReady)
        {
            return;
        }

        await _schemaLock.WaitAsync(cancellationToken);
        try
        {
            if (_schemaReady)
            {
                return;
            }

            await using var command = dataSource.CreateCommand(
                """
                CREATE TABLE IF NOT EXISTS links (
                    code            TEXT PRIMARY KEY,
                    target_url      TEXT NOT NULL,
                    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
                    clicks          BIGINT NOT NULL DEFAULT 0,
                    last_clicked_at TIMESTAMPTZ
                )
                """);
            await command.ExecuteNonQueryAsync(cancellationToken);
            _schemaReady = true;
        }
        finally
        {
            _schemaLock.Release();
        }
    }

    private static string GenerateCode() =>
        RandomNumberGenerator.GetString(CodeAlphabet, GeneratedCodeLength);
}

/// <summary>The link couldn't be added; the message says why, and is safe to show.</summary>
public sealed class LinkValidationException(string message) : Exception(message);
