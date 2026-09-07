# PowerShell Infrastructure Toolkit

Scripts I wrote to solve problems in environments I administered — mostly
around visibility: knowing what's about to break before it does, and knowing
what you actually have when nobody documented it.

Every script here was written for a real need, not as an exercise. They're
parameterised and sanitised so they run anywhere, but the reason each one
exists is in its `.DESCRIPTION` block.

## Scripts

| Script | What it does |
|---|---|
| `Certificates/Get-CertificateExpiry.ps1` | Connects to endpoints, reads the served certificate, flags anything expiring inside a threshold |
| `Infrastructure/Test-ServerHealth.ps1` | Uptime, memory pressure, low-space volumes, stopped automatic services and pending reboot in a single pass |
| `AD/Get-ADUserAudit.ps1` | Enabled accounts that are stale, have non-expiring or ageing passwords, or hold privileged group membership |

## Usage

All scripts are functions with comment-based help. Dot-source and run:

```powershell
. .\Certificates\Get-CertificateExpiry.ps1
Get-Help Get-CertificateExpiry -Full

Get-CertificateExpiry -Endpoint 'example.com','example.org:8443' -WarningDays 45
```

Output is objects, so results pipe into filtering, export or a scheduled task:

```powershell
# Servers that need attention this morning
Get-Content .\servers.txt | Test-ServerHealth |
    Where-Object { $_.PendingReboot -or $_.LowSpaceVolumes -or -not $_.Reachable }

# Privileged accounts that nobody has used in three months
Get-ADUserAudit | Where-Object { $_.Privileged -and $_.Stale } |
    Export-Csv .\privileged_stale.csv -NoTypeInformation -Encoding UTF8
```

## Design notes

A few decisions are deliberate and worth stating, since they are also the
scripts' limitations:

- **Failures are reported, not thrown.** An unreachable host returns a row
  with `Reachable = $false` and the reason in `Error`, rather than aborting
  the run. The point is a complete picture in one pass, including what
  cannot be seen.
- **`Get-CertificateExpiry` bypasses chain validation on purpose.** Expired,
  self-signed and hostname-mismatched certificates still need to be read —
  those are exactly the cases it exists to find. As a result it reports on
  expiry only, not on chain validity or hostname match.
- **`Get-ADUserAudit` reads `lastLogonTimestamp`**, which replicates on a
  delay of up to 14 days. Accounts near the cutoff can look stale when they
  are not, so the output is a shortlist to review rather than an authority
  to disable on.
- **Objects, not formatted text.** Nothing writes to the console directly,
  so everything composes with the rest of PowerShell.

## Requirements

- PowerShell 5.1 or 7.x
- Local administrator rights on any remote target
- WinRM enabled for remote queries; local queries fall back to DCOM
- `ActiveDirectory` module (RSAT) for the AD scripts

## Notes

No credentials, hostnames or environment-specific data are committed here.
Anything site-specific is passed as a parameter.

---

Marko Vuksanovic — [LinkedIn](https://linkedin.com/in/markovuksanovic-078621307)
