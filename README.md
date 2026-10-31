```
ooooo                                      oooo  oooo              
`888'                                      `888  `888              
 888          .ooooo.   .ooooo.   .oooo.    888   888  oooo    ooo 
 888         d88' `88b d88' `"Y8 `P  )88b   888   888   `88.  .8'
 888         888   888 888        .oP"888   888   888    `88..8'
 888       o 888   888 888   .o8 d8(  888   888   888     `888'
o888ooooood8 `Y8bod8P' `Y8bod8P' `Y888""8o o888o o888o     .8'
                                                       .o..P'
                                                       `Y8P'
```

# Example: A URL shortener on Function Apps, App Service and PostgreSQL within Locally

This example deploys a small URL shortener, written in C# on .NET 10, to [Locally Build](https://locally.build) or Azure. It has two parts:

* A **Function App** that serves the short links. `GET /<code>` looks the code up, counts the click and redirects to the target.
* An **admin site** on App Service, where admins add and remove links and see how often each one has been followed. Admins sign in with **App Service Authentication** against Locally's Directory Emulator.

Both store links in **Azure Database for PostgreSQL Flexible Server** and send telemetry, including a custom event for every link created, deleted and followed, to a single **Application Insights** resource.

```
                      ┌───────────────────────────────┐
  visitor ── GET /abc ─▶ Function App (.NET isolated)  │── 302 ──▶ https://the/long/url
                      │   Redirect: FollowAsync(code)  │
                      └──────────┬──────────┬──────────┘
                                 │          │ LinkFollowed / LinkNotFound
                     clicks + 1  │          ▼
                                 ▼     Application Insights ──▶ Log Analytics
                      PostgreSQL Flexible   ▲
                      Server ("links" db)   │ LinkCreated / LinkDeleted
                                 ▲          │
                      ┌──────────┴──────────┴──────────┐
  admin ── Entra ─────▶ App Service (ASP.NET Core)     │
                      │   add / remove links           │
                      └────────────────────────────────┘
```

The code lives in [`src/`](./src):

* [`UrlShortener.Functions`](./src/UrlShortener.Functions) is the Function App. [`host.json`](./src/UrlShortener.Functions/host.json) clears the `api` route prefix, so a short link is just `https://<function app>/<code>`.
* [`UrlShortener.Admin`](./src/UrlShortener.Admin) is the admin site, built with Razor Pages.
* [`UrlShortener.Data`](./src/UrlShortener.Data) is shared by both. It holds the `links` table and the PostgreSQL connection, and either app creates the table if it doesn't exist yet.

### No secrets in app settings

Both apps run as one **user-assigned managed identity**:

* It is the PostgreSQL server's **Entra administrator**. The apps get an Entra access token for it and present the token as the database password (Npgsql's periodic password provider refreshes it before it expires), so there's no `PGPASSWORD`.
* It holds **Monitoring Metrics Publisher** on Application Insights, which has local authentication turned off. The instrumentation key in the connection string is only an address and can't be used to send telemetry by itself. Each batch carries a token for the identity: the apps set it with `SetAzureTokenCredential`, and the Functions host's own telemetry uses `APPLICATIONINSIGHTS_AUTHENTICATION_STRING`.

### Signing in to the admin site

The admin site has no sign-in of its own. [App Service Authentication](./modules/function-app-url-shortener/8-admin-app.tf) (EasyAuth) signs users in before a request reaches the app, using a Microsoft Entra [app registration](./modules/function-app-url-shortener/7-entra-application.tf) that this example creates in Locally's [Directory Emulator](https://locally.build/docs/data-plane-emulators/directory-emulator). App Service then passes the signed-in user to the app in the `X-MS-CLIENT-PRINCIPAL` header, and a [small authentication handler](./src/UrlShortener.Admin/AppServiceAuthenticationHandler.cs) turns that into the request's user.

Signing in isn't enough by itself. The app registration defines an **Admin** app role, and every admin page requires it. The role always goes to whoever runs Terraform, which against Locally is the **Default Identity** at the top of the sign-in page (the identity `locally run` deploys as). Here it's also assigned to the seeded **Platform Admins** group: Ada Lovelace, Douglas Engelbart, Edsger Dijkstra and John von Neumann. Anyone else can sign in but is shown a "you're not an admin" page. To change who's an admin, set `admin_principal_ids` in [`environments/locally/providers.tf`](./environments/locally/providers.tf) to any users' or groups' object IDs.

The `LinkCreated` and `LinkDeleted` events record which admin made the change.

**Sign out** ends two sessions. `/.auth/logout` ends App Service's, then App Service passes you on to the directory's own sign-out. Without that second step, the directory would still remember who you are, and signing in again would quietly sign you back in as the same person. On Azure, the directory then returns you to the admin site's `/signed-out` page. Locally's directory stops at its own "You have signed out" page instead. Open the admin site again to pick someone else.

### Deploying the code with the publish profile

Terraform creates both apps empty, then publishes the code into them [the way Visual Studio does](./modules/function-app-url-shortener/9-deploy.tf). It runs the .NET SDK with a publish profile ([`ZipDeploy.pubxml`](./src/UrlShortener.Admin/Properties/PublishProfiles/ZipDeploy.pubxml)) and signs in to each app's SCM site with its **publishing credentials**, the `$<app>` user and password from the app's publish profile.

The profile uses the **ZipDeploy** method rather than MSDeploy (Web Deploy). Web Deploy is Windows-only at both ends: Azure only offers it for Windows apps, and `msdeploy` doesn't run on macOS or Linux. Locally runs Linux apps, and its SCM site serves `/api/zipdeploy` but not `/msdeploy.axd`. ZipDeploy is what Visual Studio and `dotnet publish` use for Linux App Service. It uses the same publish profile and the same credentials, so `webdeploy_publish_basic_authentication_enabled` stays on.

Locally names an app's SCM site `<app>-scm.furnace.locally:5663`, while Azure names it `<app>.scm.azurewebsites.net`. `locally run` sets `TF_VAR_environment_is_locally=true`, and Terraform uses it to choose the right one.

## Requirements

* [Locally Build](https://locally.build).
* Either [HashiCorp Terraform](https://terraform.io) or [OpenTofu](https://opentofu.org).
* Either [Docker](https://www.docker.com) or [Podman](https://podman.io) (recommended).
* The [.NET SDK](https://dotnet.microsoft.com/download) 10, which Terraform runs to publish the apps.
* The Locally Plugin for `Microsoft.DBforPostgreSQL` installed (`locally plugin install --name Microsoft.DBforPostgreSQL`).
* The Locally Plugin for `Microsoft.Insights` installed (`locally plugin install --name Microsoft.Insights`).
* The Locally Plugin for `Microsoft.OperationalInsights` installed (`locally plugin install --name Microsoft.OperationalInsights`).
* The Locally Plugin for `Microsoft.Storage` installed (`locally plugin install --name Microsoft.Storage`).
* The Locally Plugin for `Microsoft.Web` installed (`locally plugin install --name Microsoft.Web`).

## Running the example

First, make sure your container runtime (Docker or Podman) is running, then start Locally:

```bash
locally build
```

With Locally running, open another terminal and initialise Terraform. This downloads the providers and sets up the module:

```bash
cd environments/locally
terraform init
```

> [!NOTE]
> You can use OpenTofu instead by running `tofu` wherever this says `terraform`.

Once Terraform is initialised, provision the example:

```bash
locally run terraform apply
```

A single apply creates the PostgreSQL server and database, the managed identity and its grants, Application Insights, the app registration and its role assignment, both apps, and then publishes the code into each app. When it finishes, the URLs are in the outputs:

```
admin_url           = "https://locally-example-links-admin.furnace.locally:5663"
short_link_base_url = "https://locally-example-links-func.furnace.locally:5663"
```

[Open the admin site](https://locally-example-links-admin.furnace.locally:5663). App Service sends you to Locally's sign-in page, where you pick who to sign in as. You don't need a username or password, since this is all within Locally. Pick **Default Identity**, or someone in Platform Admins such as **Ada Lovelace**, and you're returned to the admin site. (Pick anyone else, such as Alan Turing, to see the role check refuse you.)

Add a link: give it a target URL and, optionally, a code (one is generated if you leave it blank). Then follow the short link it shows. You'll be redirected to the target, and the click count on the admin page goes up.

---

You can follow links from the command line too:

```bash
curl -si "$(locally run terraform output -raw short_link_base_url)/<code>"
```

That returns a `302` with the target in `Location`, or a `404` if there's no link with that code.

---

Every link created, deleted and followed is recorded as a custom event in Application Insights. You can query them in [the Monitoring section of the Locally Dashboard](https://localhost:5678/monitoring/components):

```
AppEvents
| where Name in ("LinkCreated", "LinkDeleted", "LinkFollowed", "LinkNotFound")
| project TimeGenerated, Name, AppRoleName, Properties
| order by TimeGenerated desc
```

For example, the most-followed links:

```
AppEvents
| where Name == "LinkFollowed"
| summarize Clicks = count() by Code = tostring(Properties.code)
| order by Clicks desc
```

The admin site's requests are in `AppRequests`, and both apps' PostgreSQL calls are in `AppDependencies`.

## Notes

The click count shown on the admin page is stored in PostgreSQL alongside the link. Application Insights holds each individual click.

`LinkFollowed` and `LinkNotFound` events include the visitor's `referrer` and `userAgent` when the Function App receives those headers, as it does on Azure. Locally doesn't currently pass request headers through to a .NET isolated worker, so locally those properties are empty and Application Insights leaves them out. For the same reason, the Function App's own requests don't show up in `AppRequests` locally. Its PostgreSQL calls and custom events do.

Links redirect with `302` rather than `301`. Browsers cache a `301` indefinitely, so later clicks wouldn't reach the Function App to be counted, and a removed link would keep working for anyone who had already followed it.

The codes `admin`, `api` and `runtime` are reserved. With an empty route prefix, the Functions host keeps those paths for itself.

The connection to PostgreSQL is always encrypted with TLS. The server certificate is verified only when you set `PG_CA_CERT` to the path of a CA certificate. Do this against Azure, using the DigiCert Global Root. Locally's emulator uses a certificate the apps don't trust, so verification is skipped by default.

The admin site's `authority_host` is `https://127.0.0.1:5677` rather than `https://auth.locally:5677`. Locally's App Service Authentication sends sign-ins to `127.0.0.1:5677` whichever is configured, so that's where the directory's session cookie lives, and signing out has to go there too.

The admin site asks for `prompt=select_account` on every sign-in (`login_parameters` in `auth_settings_v2`), so Azure always shows the account picker. Locally stores the setting but doesn't yet add it to the sign-in request, which is why signing out also ends the directory's session.

App Service removes any `X-MS-CLIENT-PRINCIPAL` header a caller sends, so the app can trust the one it receives. That only holds while App Service is the only way to reach the app.

Both apps are republished whenever anything under `src/` changes. Terraform hashes the source and republishes when the hash changes. Because the publishing credentials are sensitive, Terraform hides the publish output. It's written to `.build/<app>-publish.log` instead, so look there if a publish fails. To publish by hand, set `DeployHost`, `DeployUserName` and `DeployPassword` (see the comments in the publish profiles), then run `dotnet publish -c Release -p:PublishProfile=ZipDeploy` in `src/UrlShortener.Admin`, or `dotnet build -c Release -p:DeployOnBuild=true -p:PublishProfile=ZipDeploy` in `src/UrlShortener.Functions`. The Function App needs the second form because `dotnet publish` only runs the deploy step for ASP.NET Core projects.

## Running this on Azure

The same module deploys to Azure from [`environments/azure`](./environments/azure). Compared with Locally:

* Admins sign in with Microsoft Entra ID (`https://login.microsoftonline.com`), in your own tenant. Whoever runs Terraform gets the Admin role. To add more admins, set `admin_principal_ids` to the object IDs of users or groups in your tenant. Assigning an app role to a group needs Microsoft Entra ID P1.
* Resource names get a random suffix (`links-<suffix>-…`), as App Service, PostgreSQL and Storage Account names have to be unique across all of Azure.
* The region defaults to `westeurope`. Set `location` to change it.
* The Log Analytics workspace has a daily ingestion cap of 0.5 GB (`log_analytics_daily_quota_gb`). See the costs below.

You'll need permission to create app registrations in your tenant, and Azure Policy must allow basic authentication for publishing, since the code is deployed with the apps' publishing credentials. Many organisations restrict one or both of these.

```bash
az login
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

cd environments/azure
terraform init
terraform apply
```

Run it without `locally run`. That's what points Terraform at Azure rather than Locally. (If you did use `locally run` here, Locally would refuse the `westeurope` region, so nothing would reach Azure by accident.)

State is kept in a local file. For a shared or long-lived deployment, uncomment the `backend "azurerm"` block in [`providers.tf`](./environments/azure/providers.tf) and point it at a storage account.

The connection to PostgreSQL is encrypted, but the server's certificate isn't checked unless you set `PG_CA_CERT` (see the notes above). On Azure, you should.

### What it costs

Pay-as-you-go list prices in West Europe, in USD, from the [Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices) in October 2026:

| Resource | Price | Per month |
|---|---|---|
| App Service plan, Linux B1 (shared by both apps) | $0.018/hour | ~$13.14 |
| PostgreSQL Flexible Server, Burstable B1ms | $0.0199/hour | ~$14.53 |
| PostgreSQL storage, 32 GB | $0.1369/GB/month | ~$4.38 |
| PostgreSQL backups | Free up to the server's storage size, then $0.103/GB/month | $0 |
| Log Analytics ingestion (Application Insights' data) | First 5 GB/month free, then $2.99/GB | ~$0 (see below) |
| Log Analytics retention | 30 days included; $0.13/GB/month beyond that | $0 |
| Storage Account (the Functions host's) | Pennies | ~$0 |
| **Total** | | **~$32** |

Log Analytics is the one to watch. It's billed per GB ingested, and the bill tracks traffic and log levels rather than anything fixed. This app sends little: a request, a database call and a custom event per redirect, at most a few KB each. Even hundreds of thousands of redirects a month stay inside the free 5 GB. What runs up Log Analytics bills is usually verbose logging (Debug or Trace levels, or diagnostic settings sending platform logs too), which this example doesn't turn on.

The 0.5 GB daily cap limits the worst case to about 15 GB a month, around $30 past the free 5 GB. When the cap is reached, ingestion stops until the next day, so you'd lose telemetry rather than money. Raise it, or set it to `-1` to remove it, once you know your volumes.

App Service and PostgreSQL bill by the hour whether they're used or not. Run `terraform destroy` when you're done.

## Tearing it down

```bash
cd environments/locally
locally run terraform destroy
```

On Azure, run `terraform destroy` in `environments/azure` instead.
