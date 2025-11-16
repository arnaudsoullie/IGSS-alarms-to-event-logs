# IGSS Alarms to Event Logs

PowerShell script to export and parse CSV alarm files from [IGSS SCADA](https://igss.schneider-electric.com/) software and write them to Windows Application Event Log (to be able to forward them to a cybersecurity monitoring solution)

## Overview

This script processes alarm data from CSV files and creates structured events in the Windows Application Event Log. It supports:

- **Column index-based parsing** - Works with CSV files in any language
- **Event ID mapping** - Map different alarm types to specific Event IDs
- **Entry Type mapping** - Assign severity levels (Information, Warning, Error) based on alarm text
- **IP Address mapping** - Map Node IDs (IGSS representation of PLCs) to IP addresses
- **SHA-256 hashing** - Generate unique hashes for each alarm record for deduplication on the SIEM side
- **Export command support** - Run IGSS ``alm.exe`` commands to export the alarms before processing
- **Test mode** - Preview events without writing to the event log

## Requirements

- Windows PowerShell 5.1 or later
- Administrator privileges (required on first run to register event log source)

## Installation

1. Copy `process_alarms.ps1` to your desired location
2. Ensure you have read access to your CSV files
3. Run the script with Administrator privileges on first execution
4. Setup a scheduled tasks to regularly export the alarms

## Configuration

### Column Index Configuration

Edit the `$columnIndices` hashtable to match your CSV structure (0-based indices):

```powershell
$columnIndices = @{
    DateDebut     = 2   # Column index for start date
    HreDebut      = 3   # Column index for start time
    TexteAlarme   = 11  # Column index for alarm text
    NoeudID       = 18  # Column index for node ID
}
```

### Event ID Mapping

Map alarm text values to specific Event IDs:

```powershell
$eventIdMapping = @{
    "PLC progam change"     = 1001
    "PLC not running"       = 1002
    # Add more mappings as needed
}
```

### Entry Type Mapping

Map alarm text values to severity levels:

```powershell
$entryTypeMapping = @{
    "PLC progam change"     = "Information"
    "PLC not running"       = "Warning"
    # Valid values: Information, Warning, Error, SuccessAudit, FailureAudit
}
```

### IP Address Mapping

Map Node IDs to IP addresses:

```powershell
$noeudIdToIpMapping = @{
    "0"     = "192.168.1.100"
    "1"     = "192.168.1.101"
    # Add more mappings as needed
}
```

### Export Command Configuration

Configure the command to run before processing (when using `-ExportAlarms`):

```powershell
$exportAlarmsCommand = "C:\Program Files\IGSS\ExportAlarms.exe -output `"$CsvPath`""
```

Example:

 `"C:\Program Files\IGSS\ExportAlarms.exe -output `"$CsvPath`""`


## Usage

### Run headless (no window) via VBScript

To prevent PowerShell or console windows from popping up (e.g., when scheduled), launch the export and processing commands via a VBScript that runs them hidden.

Example `scheduled_task_script.vbs` (included in this repo):

```vb
Set objShell = CreateObject("WScript.Shell")

' 1) Export alarms (runs hidden, waits until completion)
command1 = """C:\Program Files (x86)\Schneider Electric\IGSS32\V14.0\GSS\alm.exe"" -fsiem -csv -file""C:\Users\lab\Documents\igss_alarms.csv"" -ts$-90 -te$ -all"
objShell.Run command1, 0, True

' 2) Process alarms (runs hidden, waits until completion)
command2 = "powershell.exe -NoLogo -NonInteractive -WindowStyle Hidden -File ""C:\Users\lab\Documents\process_alarms.ps1"" -ExportAlarms -CsvPath ""C:\Users\lab\Documents\igss_alarms.csv"""
objShell.Run command2, 0, True
```

- WindowStyle 0 ensures the commands run hidden.
- The last parameter `True` makes the VBScript wait synchronously before running the next command.

Schedule it with Windows Task Scheduler:
- Program/script: `wscript.exe`
- Add arguments: `"C:\Path\To\scheduled_task_script.vbs"`
- Configure “Run whether user is logged on or not” and “Hidden”.

### Basic Usage

```powershell

# Process a specific CSV file
.\process_alarms.ps1 -CsvPath "C:\data\alarms.csv"
```

### Test Mode

Preview events without writing to the event log:

```powershell
# Test with default CSV file
.\process_alarms.ps1 -Test

# Test with specific CSV file
.\process_alarms.ps1 -Test -CsvPath "alarms.csv"
```

### Export Alarms

Run export command before processing:

```powershell
.\process_alarms.ps1 -ExportAlarms -CsvPath "alarms.csv"
```


## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-CsvPath` | String | No | `"test_data.csv"` | Path to the CSV file to process |
| `-Test` | Switch | No | - | Enable test mode (display events without writing to event log) |
| `-ExportAlarms` | Switch | No | - | Run export command before processing CSV |

## Event Log Output

Each event written to the Windows Application Event Log contains:

- **Log Name**: Application
- **Source**: IGSS-Alarms
- **Event ID**: Mapped based on alarm text (or default: 1000)
- **Entry Type**: Mapped based on alarm text (or default: Information)
- **Message**: Formatted text containing:
  - Hash: SHA-256 hash of all CSV columns
  - StartDate: Alarm start date
  - StartTime: Alarm start time
  - AlarmText: Alarm description text
  - IPAddress: Mapped IP address (or Node ID if no mapping)

## Viewing Events

View events in Windows Event Viewer:

1. Open **Event Viewer** (`eventvwr.msi`)
2. Navigate to **Windows Logs** > **Application**
3. Filter by **Source**: `IGSS-Alarms`
4. Filter by **Event ID** if needed

Or use PowerShell:

```powershell
# View recent IGSS-Alarms events
Get-EventLog -LogName Application -Source "IGSS-Alarms" -Newest 10

# Filter by Event ID
Get-EventLog -LogName Application -Source "IGSS-Alarms" | Where-Object { $_.EventID -eq 1001 }
```

## Wazuh SIEM Integration (XML Rules)

This repository includes a Wazuh rules file `igss_alarms.xml` to process the Windows Application log events produced by this script.

What it does:
- Matches Application log events from `IGSS-Alarms`
- Looks for specific Event IDs (e.g., 1001, 1002)
- Adds context and groups alarms under `igss, scada`

Install on the Wazuh manager:
1. Copy `igss_alarms.xml` to your Wazuh manager:
   - Recommended path: `/var/ossec/etc/rules/igss_alarms_rules.xml`
2. Validate and restart Wazuh:
   ```bash
   sudo /var/ossec/bin/wazuh-logtest -t
   sudo systemctl restart wazuh-manager
   ```
3. Test the rule:
   ```bash
   sudo /var/ossec/bin/wazuh-logtest
   ```
   Paste a sample Windows event content that includes:
   - ProviderName: IGSS-Alarms
   - EventID: 1001 (or 1002)

Notes:
- The rules in `igss_alarms.xml` rely on Windows EventChannel fields (e.g., `win.system.providerName`, `win.system.eventID`).
- Ensure your Wazuh agent on Windows is collecting the Application event log (EventChannel input enabled).


## Error Handling

- **Export command failures**: Script exits with the command's exit code
- **CSV file not found**: Script exits with error code 1
- **Event log write failures**: Error is logged, script continues with next record
- **Missing mappings**: Uses default values (Event ID: 1000, Entry Type: Information)





