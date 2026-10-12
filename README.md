# Set-FinOpsSandboxUpdateCadence.ps1

Interactively signs in to a Power Platform tenant, lists every Finance &
Operations (F&O) environment and its maintenance cadence, then lets you set the
major-version update cadence ("Every Update" / "Every other Update") for all
F&O **Sandbox** environments in that tenant.

## Prerequisites

| # | Requirement | Why | Install / check |
|---|---|---|---|
| 1 | **PowerShell 5.1+ (Windows PowerShell) or PowerShell 7+** | Runs the script. | Windows PowerShell 5.1 ships with Windows 10/11. For cross-platform PowerShell 7, see [Installing PowerShell](https://learn.microsoft.com/powershell/scripting/install/installing-powershell). |
| 2 | **Microsoft Power Platform CLI (`pac`), version 2.12 or later** | Provides every command the script calls (`pac auth`, `pac admin`, `pac dynamics`, `pac environment-management`). Versions older than ~2.12 don't have the `dynamics`/`environment-management` command groups and will fail with `Error: Not a valid command.` | See **Installing pac CLI** below. |
| 3 | **A PowerShell execution policy that allows running local scripts** | The script isn't code-signed. | Run once per session: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned`, or run via `powershell -ExecutionPolicy Bypass -File .\Set-FinOpsSandboxUpdateCadence.ps1`. See [about_Execution_Policies](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies). |
| 4 | **A Microsoft Entra ID / Microsoft 365 account with admin rights on the target tenant** | Needed to list environments tenant-wide and change F&O maintenance settings. Typically **Dynamics 365 Administrator** or **Power Platform Administrator** (Global Administrator also works). | Check/assign at [Microsoft 365 admin center > Roles](https://admin.microsoft.com/Adminportal/Home#/roles) or [Power Platform admin center](https://admin.powerplatform.microsoft.com/). |
| 5 | **Network access to Microsoft sign-in and Power Platform admin endpoints** | The script opens an interactive (or device-code) sign-in and calls Power Platform admin APIs. | Ensure `login.microsoftonline.com` and `*.admin.powerplatform.microsoft.com` / `*.api.powerplatform.com` aren't blocked by a firewall/proxy. |

## Installing pac CLI

Pick **one** of these (don't mix — if you already have one installed, just make sure it's updated per the note below):

- **VS Code extension (recommended if you use VS Code):** install [Power Platform Tools](https://marketplace.visualstudio.com/items?itemName=microsoft-IsvExpTools.powerplatform-vscode) from the VS Code Marketplace. It bundles `pac` and keeps it updated automatically.
- **Standalone CLI (Windows, no VS Code needed):** follow [Install the Power Platform CLI](https://learn.microsoft.com/power-platform/developer/cli/introduction#install-the-cli-standalone) for the MSI/zip download.
- **.NET tool (Windows/macOS/Linux, requires the [.NET SDK](https://dotnet.microsoft.com/download) 6.0+):**
  ```
  dotnet tool install --global Microsoft.PowerApps.CLI.Tool
  ```

> **Important:** this script needs the `pac dynamics` and `pac environment-management` command groups, which are newer preview additions. After installing, update to the latest build and confirm:
> ```
> pac install latest      # standalone/MSI installs
> dotnet tool update -g Microsoft.PowerApps.CLI.Tool   # .NET tool installs
> pac dynamics help       # should list get-fin-ops-maintenance-settings, etc. - not an "Error: Not a valid command"
> ```
> If you have multiple `pac` installs on PATH (common if you've used both VS Code and a standalone install), run `where.exe pac` (Windows) or `which -a pac` (macOS/Linux) to see which one resolves first, and update that one.

Full official docs: [Power Platform CLI overview](https://learn.microsoft.com/power-platform/developer/cli/introduction).

## Running it

```powershell
.\Set-FinOpsSandboxUpdateCadence.ps1
```

Optional parameters:
```powershell
.\Set-FinOpsSandboxUpdateCadence.ps1 -TenantId contoso.onmicrosoft.com   # pin sign-in to a specific tenant
.\Set-FinOpsSandboxUpdateCadence.ps1 -DeviceCode                         # device-code sign-in (headless/remote machines)
```

No tenant-specific URLs, IDs, or credentials are embedded in the script — everything is discovered live from whichever tenant you sign in to.
