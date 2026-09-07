# PowerShell Infrastructure Toolkit

Scripts I wrote to solve problems in environments I administered — mostly
around visibility: knowing what's about to break before it does.

Every script here was written for a real need, not as an exercise. They're
parameterised and sanitised so they run anywhere, but the reason each one
exists is in its `.DESCRIPTION` block.

## Scripts

| Script | What it does |
|---|---|
| `Certificates/Get-CertificateExpiry.ps1` | Connects to endpoints, reads the served certificate, flags anything expiring inside a threshold |
| `Infrastructure/Test-ServerHealth.ps1` | Uptime, memory pressure, low-space volumes, stopped automatic services and pending reboot in a single pass |

## Usage

All scripts are functions with comment-based help. Dot-source and run:

```powershell
. .\Certificates\Get-CertificateExpiry.ps1
Get-Help Get-CertificateExpiry -Full

Get-CertificateExpiry -Endpoint 'example.com','example.org:8443' -WarningDays 45
```

Output is objects, so it pipes into `Where-Object`, `Export-Csv` or a
scheduled task that mails the result:

```powershell
Get-Content .\servers.txt | Test-ServerHealth |
    Where-Object { $_.PendingReboot -or $_.LowSpaceVolumes } |
    Export-Csv .\attention.csv -NoTypeInformation
```

## Requirements

- PowerShell 5.1 or 7.x
- Local administrator rights on any remote target
- WinRM enabled for remote queries; local queries fall back to DCOM

## Notes

No credentials, hostnames or environment-specific data are committed here.
Anything site-specific is passed as a parameter.

---

Marko Vuksanovic — [LinkedIn](https://linkedin.com/in/markovuksanovic-078621307)
