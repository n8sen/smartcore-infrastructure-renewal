# SmartCore Infrastructure Renewal

> Windows Server 2025 enterprise infrastructure design and deployment — John Bryce Academy project by Nate Sendler (8855-12)

---

## Overview

This project documents the full design and deployment of a modern enterprise IT infrastructure for **SmartCore**, a mid-sized international company operating across two sites: **Tel Aviv (HQ)** and **New York**. The environment is built on Windows Server 2025 and covers identity management, virtualization, network services, security, remote access, and backup.

The Tel Aviv site was fully implemented and documented. The New York site is covered by a detailed SOP (Standard Operating Procedure) allowing a remote team member to replicate the environment independently.

---

## Company Profile

| Property | Detail |
|---|---|
| Sites | Tel Aviv HQ · New York Division |
| Total users | ~215 |
| Distribution | 80% Tel Aviv / 20% New York |
| Domain | `smartcore.com` |

**Departments:** Sales, Management, CS, Finance, Logistics, Operations, HR

---

## Architecture

### Physical Hosts — one per site

| Spec | Value |
|---|---|
| Model | Dell PowerEdge R760 |
| CPU | 2× Intel Xeon Gold 6430 (64 cores total) |
| RAM | 256GB DDR5 |
| VM Storage | 40TB RAID10 (10× 4TB Samsung PM893) |
| OS Storage | 2TB RAID1 (2× Samsung PM9A3 960) |
| NIC | 2× Intel X710 |
| Hypervisor | Windows Server 2025 / Hyper-V |

### IP Scheme

| Site | Network |
|---|---|
| Tel Aviv HQ | `172.16.10.0/24` |
| New York | `172.16.20.0/24` |

### VLAN Segmentation

| VLAN | Purpose | TA Subnet | NY Subnet |
|---|---|---|---|
| 10 | Servers | `172.16.10.0/28` | `172.16.20.0/28` |
| 20 | Storage (iSCSI) | `172.16.10.16/29` | `172.16.20.16/29` |
| 30 | Management | `172.16.10.24/29` | `172.16.20.24/29` |
| 40 | Clients | `172.16.10.32/27` | `172.16.20.128/25` |
| 50–60 | Reserved for scale-up | `172.16.10.64/26` · `/128/25` | — |

Sites are connected via a **VPN tunnel**. Each site has dual ISP lines: primary at 1/1 Gbps and secondary at 200/10 Mbps.

---

## Virtual Machines

| VM | Roles | vCPU | RAM | Storage | IP (TA / NY) |
|---|---|---|---|---|---|
| `XX-DC1` | ADDS, DNS | 2 | 8GB | 80GB | `.2` |
| `TA-FS1` | DFS, DHCP | 4 | 16GB | 100GB + 2TB | `10.3` |
| `TA-FS2` | DFS, IIS | 4 | 16GB | 100GB + 2TB | `10.4` |
| `NY-FS1` | DFS-R, DHCP, IIS | 4 | 16GB | 100GB + 2TB | `20.3` |
| `XX-ST1` | iSCSI Target | 8 | 32GB | 100GB + 8TB | `.18` |
| `XX-RDS1` | RDS | 8 | 32GB | 100GB + 200GB | `10.5` / `20.4` |
| `TA-CA1` | ADCS (HQ only) | 2 | 4GB | 80GB | `10.6` |
| `FW1/FW2` | pfSense, VPN, NAT, HA | 4 | 8GB | 40GB | VIPs per site |

> Tel Aviv HQ carries 80% of users and runs split file services (FS1 + FS2) for load distribution and resilience. If one fails, only DHCP or IIS is lost — not both.

---

## Services Deployed

### Active Directory Domain Services (ADDS)
- Domain: `smartcore.com`
- NY-DC1 promoted as additional DC replicating from `TA-DC1.smartcore.com`
- OU topology mirrors each site: `Admins`, `Computers/Servers`, `Computers/Workstations`, `Groups`, `Users/<Department>`
- AD Recycle Bin enabled
- Replication verified via `repadmin /syncall /AeD` and `repadmin /replsummary`

### DNS
- Forward and reverse lookup zones configured per site
- Conditional forwarder set between TA and NY DNS servers
- `portal.smartcore.com` and `certportal.smartcore.com` A records configured

### DHCP
- Scopes configured per VLAN subnet
- Failover configured between `TA-FS1` and `NY-FS1` in **50/50 load-balanced mode**
- DHCP relay (IP Helper) required on firewall/router for cross-VLAN client VLANs (40, 50, 60)

### DFS (Distributed File System)
- Namespace: `\\smartcore.com\DFS`
- Namespace servers: TA-FS1, TA-FS2, NY-FS1
- Dedicated division folders per site (e.g. `Finance-NY`)
- Per-folder quota: 500GB hard limit with email + event log warnings at 85% and 100%
- Division folder shortcuts mapped to user desktops via per-OU GPOs (`%division% Drive Mapping NY`)

### ADCS (Certificate Authority)
- Enterprise Root CA on `TA-CA1` — HQ only, centralized for security
- Algorithm: RSA 4096 / SHA-512
- Custom templates: `WebServer2`, `Computer2`
- Auto-enrollment via `SmartcoreGPO` (GPO linked domain-wide)
- Full auditing enabled on the CA

### IIS (Intranet Portal)
- Portal site: `https://portal.smartcore.com` — HTTPS bound with issued certificate
- CRL distribution site: `http://certportal.smartcore.com` — directory browsing enabled
- Portal redirects authenticated users to RDS Web Access login

### RDS (Remote Desktop Services)
- Deployed on `XX-RDS1` per site
- Access restricted to `PrivilegedAccounts` security group via GPO (`RDS Access-NY`)
- Domain Users explicitly removed from Remote Desktop Users group
- Management tools installed on RDS without role installation (RSAT, Hyper-V tools, DFS tools, etc.)

### Users & Groups
- Users bulk-created from CSV via PowerShell script
- Default password format: `{First initial}{Last initial}sm2026!` — must change on first login
- UPN format: `{firstname}{first 2 of lastname}@smartcore.com`
- Privileged admin accounts follow `a_%username%` naming convention, placed in `OU=Admins`
- Fine-Grained Password Policy (`PrivilegedAccounts` FGPP): 12-char minimum, complexity required, 5 password history, 3 failed attempts → 30-min lockout

### DC Backup
- Weekly full backup via `wbadmin` to `\\TA-FS1.smartcore.com\Backup`
- Automated via Task Scheduler (`SrvBackup` task) — runs with highest privileges, restarts on failure up to 3 times

---

## Repository Structure

```
smartcore-infrastructure-renewal/
├── README.md
├── docs/
│   └── SmartCore_Project.pdf          # Full project report with screenshots
├── scripts/
│   ├── HyprV_VMcreation.ps1           # Automated VM provisioning via Hyper-V
│   └── Create-SmartCoreUsers.ps1      # Bulk AD user creation from CSV
├── data/
│   └── SmartCoreWorkers.csv           # User roster with department/site mapping
└── gpo-reports/
    ├── Default_Domain_Policy.htm      # Password policy, account lockout, firewall rules
    ├── SmartcoreGPO.htm               # Certificate auto-enrollment policy
    ├── CS_Drive_Mapping.htm           # Example drive mapping GPO (CS division)
    └── RDS_Access.htm                 # RDS logon restriction GPO
```

---

## Scripts

### `HyprV_VMcreation.ps1`
Automates VM creation on the Hyper-V host. Configure the `CONFIG` section with the correct vCPU, RAM, and VHDX sizes per VM before running. Refer to the VM allocation table above.

### `Create-SmartCoreUsers.ps1`
Bulk-creates AD users from the provided CSV file.

**Parameters:**
- `CsvPath` — path to `SmartCoreWorkers.csv`
- `TargetSite` — `"Tel-Aviv"` or `"New-York"`

The script auto-creates missing OUs and logs all actions to a timestamped log file. Default passwords and UPN addresses are generated automatically per company convention.

```powershell
.\Create-SmartCoreUsers.ps1 -CsvPath "C:\Data\SmartCoreWorkers.csv" -TargetSite "New-York"
```

---

## Key Design Decisions

**Why is the CA only at HQ?**
A Certificate Authority is one of the most sensitive assets in a network — compromising it compromises the entire trust model. Centralizing it at Tel Aviv ensures tighter physical and logical security, easier auditing, and simpler revocation control.

**Why are FS1 and FS2 split at Tel Aviv?**
Tel Aviv carries 80% of the user load. Splitting DHCP + DFS onto FS1 and IIS + DFS onto FS2 means a single server failure only takes down one service, not both. NY consolidates these onto one server (NY-FS1) as its load is proportionally smaller.

**Why is RDS restricted to privileged accounts?**
RDS provides direct access to server management tools. Allowing general domain users access would expose critical infrastructure management surfaces. The `PrivilegedAccounts` FGPP also enforces a stricter password policy for these accounts specifically.

**Why VLAN segmentation?**
Each VLAN isolates a traffic class — servers, storage, management, clients. This limits blast radius if one segment is compromised, prevents iSCSI storage traffic from competing with user traffic, and makes firewall rules more precise and auditable.

---

## Author

**Nate Sendler** — John Bryce Academy, cohort 8855-12  
Contact: nate@n8sendler.tech  
Instructor: Damian Bermatov  
Date: April 12, 2026
