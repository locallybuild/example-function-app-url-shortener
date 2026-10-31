namespace UrlShortener.Admin;

public static class SignOutLink
{
    /// <summary>
    /// Where the Sign out link goes.
    ///
    /// /.auth/logout ends App Service's session, but not the directory's own,
    /// so on its own the next sign-in would quietly sign you back in as whoever
    /// signed in last. So it goes on to the directory's sign-out
    /// (ENTRA_SIGN_OUT_URL, which App Service allows it to redirect to - see
    /// 8-admin-app.tf), asking to come back to /signed-out afterwards.
    /// </summary>
    public static string Url(HttpRequest request, IConfiguration configuration)
    {
        var signedOut = $"{request.Scheme}://{request.Host}/signed-out";

        var directorySignOut = configuration["ENTRA_SIGN_OUT_URL"];
        var next = string.IsNullOrEmpty(directorySignOut)
            ? "/signed-out"
            : $"{directorySignOut}?post_logout_redirect_uri={Uri.EscapeDataString(signedOut)}";

        return $"/.auth/logout?post_logout_redirect_uri={Uri.EscapeDataString(next)}";
    }
}
