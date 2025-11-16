# PowerShell script to parse CSV and write events to Windows Application event log
# Usage: .\process_alarms.ps1 -CsvPath "test_data.csv"
#        .\process_alarms.ps1 -Test  (to display events without writing to event log)
#        .\process_alarms.ps1 -ExportAlarms  (to run export command before processing)

param(
    [Parameter(Mandatory=$false)]
    [string]$CsvPath = "test_data.csv",
    
    [Parameter(Mandatory=$false)]
    [switch]$Test,
    
    [Parameter(Mandatory=$false)]
    [switch]$ExportAlarms
)

# ============================================================================
# Event ID Mapping Configuration
# Map "Texte d'alarme" values to specific Event IDs
# ============================================================================
$eventIdMapping = @{
    "PLC progam change"     = 1001
    "PLC not running"       = 1002
    # Add more mappings as needed:
    # "Alarm Text"          = EventID
}

# Default Event ID to use if no mapping is found
$defaultEventId = 1000

# ============================================================================
# Entry Type Mapping Configuration
# Map "Texte d'alarme" values to specific Entry Types
# Valid values: Information, Warning, Error, SuccessAudit, FailureAudit
# ============================================================================
$entryTypeMapping = @{
    "PLC progam change"     = "Warning"
    "PLC not running"       = "Warning"
    # Add more mappings as needed:
    # "Alarm Text"          = "Information" | "Warning" | "Error" | "SuccessAudit" | "FailureAudit"
}

# Default Entry Type to use if no mapping is found
$defaultEntryType = "Information"

# ============================================================================
# NoeudID to IP Address Mapping Configuration
# Map NoeudID values to IP addresses
# ============================================================================
$noeudIdToIpMapping = @{
    "0"     = "192.168.1.100"
    "1"     = "192.168.1.101"
    # Add more mappings as needed:
    # "NoeudID" = "IP Address"
}

# ============================================================================
# CSV Column Index Configuration
# Define column indices (0-based) for required fields
# This allows the script to work regardless of header language
# ============================================================================
$columnIndices = @{
    DateDebut     = 2   # Column index for start date
    HreDebut      = 3   # Column index for start time
    TexteAlarme   = 11  # Column index for alarm text
    NoeudID       = 18  # Column index for node ID
}

# ============================================================================
# Export Alarms Command Configuration
# Command to execute before processing the CSV file
# This command will be run synchronously and must succeed for the script to continue
# 
# Configuration: Provide the executable path and arguments separately
# - $exportAlarmsExe: Full path to the executable (use double quotes if path contains spaces)
# - $exportAlarmsArgs: Arguments as a single string (use double quotes for values with spaces)
# 
# Note: The $CsvPath variable will be expanded when the command runs
# ============================================================================
$exportAlarmsExe = "C:\Program Files (x86)\Schneider Electric\IGSS32\V14.0\GSS\alm.exe"
# Use {CsvPath} as a placeholder that will be replaced with the actual path
# Use `$ to escape literal dollar signs in the command arguments
$exportAlarmsArgs = "-fsiem -csv -file""$CsvPath"" -ts$-90 -te$ -all"

# Examples:
# $exportAlarmsExe = "C:\Program Files\IGSS\ExportAlarms.exe"
# $exportAlarmsArgs = "-output `"{CsvPath}`""
#
# $exportAlarmsExe = "powershell.exe"
# $exportAlarmsArgs = "-File C:\Scripts\export.ps1 -OutputFile `"{CsvPath}`""

# ============================================================================
# Deduplication Configuration
# Skip writing events if an identical hash exists in the last N hours
# ============================================================================
$enableDeduplication = $true
$deduplicationLookbackHours = 1

# Execute export command if -ExportAlarms switch is provided
if ($ExportAlarms) {
    Write-Host "Running export alarms command..." -ForegroundColor Yellow
    Write-Host "Executable: $exportAlarmsExe" -ForegroundColor Gray
    Write-Host "Arguments: $exportAlarmsArgs" -ForegroundColor Gray
    
    try {
        # Verify executable exists
        if (-not (Test-Path $exportAlarmsExe)) {
            Write-Error "Export executable not found: $exportAlarmsExe"
            exit 1
        }
        
        
        # Execute command synchronously and capture exit code
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $exportAlarmsExe
        $processInfo.Arguments = $expandedArgs
        $processInfo.UseShellExecute = $false
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.CreateNoWindow = $true
        $processInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $processInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $yolo = $object | ConvertTo-Json -Depth 10
        Write-Host $yolo
        
        # Start the process
        $process.Start() | Out-Null
        
        # Capture output
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        
        # Wait for completion
        $process.WaitForExit()
        
        # Display output if any
        if ($stdout) {
            Write-Host "Command output:" -ForegroundColor Cyan
            Write-Host $stdout
        }
        if ($stderr) {
            Write-Host "Command errors:" -ForegroundColor Yellow
            Write-Host $stderr
        }
        
        if ($process.ExitCode -ne 0) {
            Write-Error "Export command failed with exit code: $($process.ExitCode)"
            exit $process.ExitCode
        }
        
        Write-Host "Export command completed successfully" -ForegroundColor Green
    } catch {
        Write-Error "Failed to execute export command: $($_.Exception.Message)"
        exit 1
    }
}

# Check if CSV file exists
if (-not (Test-Path $CsvPath)) {
    Write-Error "CSV file not found: $CsvPath"
    exit 1
}

# Register event log source if it doesn't exist (skip in test mode)
$eventSource = "IGSS-Alarms"
if (-not $Test) {
    if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
        try {
            New-EventLog -LogName Application -Source $eventSource -ErrorAction Stop
            Write-Host "Registered event log source: $eventSource" -ForegroundColor Yellow
        } catch {
            Write-Error "Failed to register event log source. You may need to run as Administrator. Error: $($_.Exception.Message)"
            exit 1
        }
    }
} else {
    Write-Host "TEST MODE: Events will be displayed but not written to event log" -ForegroundColor Yellow
}

# Function to check if an event with the same hash already exists in the lookback window
function Test-EventHashExists {
    param(
        [Parameter(Mandatory = $true)][string]$Hash,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][int]$LookbackHours
    )

    try {
        $cutoffTime = (Get-Date).AddHours(-$LookbackHours)
        $existing = Get-EventLog -LogName Application -Source $Source -After $cutoffTime -ErrorAction SilentlyContinue
        if ($null -eq $existing -or $existing.Count -eq 0) {
            return $false
        }

        foreach ($evt in $existing) {
            if ($evt.Message -like "*Hash: $Hash*") {
                return $true
            }
        }

        return $false
    } catch {
        Write-Warning "Dedup check failed: $($_.Exception.Message)"
        return $false
    }
}

# Read CSV file as raw text to access columns by index
Write-Host "Reading CSV file: $CsvPath" -ForegroundColor Green
$csvLines = Get-Content -Path $CsvPath -Encoding UTF8

if ($null -eq $csvLines -or $csvLines.Count -lt 2) {
    Write-Warning "No data found in CSV file (need at least header and one data row)"
    exit 0
}

# Skip header row and process data rows
$dataRows = $csvLines[1..($csvLines.Count - 1)] | Where-Object { $_.Trim() -ne "" }

if ($null -eq $dataRows -or $dataRows.Count -eq 0) {
    Write-Warning "No data rows found in CSV file"
    exit 0
}

Write-Host "Found $($dataRows.Count) records to process" -ForegroundColor Green

# Process each row
foreach ($line in $dataRows) {
    $columns = $null
    try {
        # Split the line by semicolon delimiter
        $columns = $line -split ';'
        
        # Extract values by column index
        $dateDebutValue = if ($columns.Count -gt $columnIndices.DateDebut) { $columns[$columnIndices.DateDebut].Trim() } else { "" }
        $hreDebutValue = if ($columns.Count -gt $columnIndices.HreDebut) { $columns[$columnIndices.HreDebut].Trim() } else { "" }
        $texteAlarmeValue = if ($columns.Count -gt $columnIndices.TexteAlarme) { $columns[$columnIndices.TexteAlarme].Trim() } else { "" }
        $noeudIDValue = if ($columns.Count -gt $columnIndices.NoeudID) { $columns[$columnIndices.NoeudID].Trim() } else { "" }
        
        # Calculate SHA-256 hash of all columns
        $hashString = ""
        for ($i = 0; $i -lt $columns.Count; $i++) {
            $hashString += "Col$i=" + $columns[$i].Trim() + "|"
        }
        
        # Remove trailing pipe
        $hashString = $hashString.TrimEnd("|")
        
        # Calculate SHA-256 hash
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($hashString))
        $hashString = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
        $sha256.Dispose()
        
        # Look up IP address for NoeudID
        $ipAddress = ""
        if ($noeudIDValue -and $noeudIdToIpMapping.ContainsKey($noeudIDValue)) {
            $ipAddress = $noeudIdToIpMapping[$noeudIDValue]
        } else {
            $ipAddress = $noeudIDValue  # Use NoeudID value if no mapping found
        }
        
        $eventMessage = "Hash: $hashString`r`n" +
                       "StartDate: $dateDebutValue`r`n" +
                       "StartTime: $hreDebutValue`r`n" +
                       "AlarmText: $texteAlarmeValue`r`n" +
                       "IPAddress: $ipAddress"
        
        # Determine Event ID and Entry Type based on "Texte d'alarme" field
        $alarmText = $texteAlarmeValue
        
        # Look up Event ID
        if ($eventIdMapping.ContainsKey($alarmText)) {
            $eventId = $eventIdMapping[$alarmText]
        } else {
            $eventId = $defaultEventId
            if ($Test) {
                Write-Host "Warning: No Event ID mapping found for '$alarmText', using default Event ID $defaultEventId" -ForegroundColor Yellow
            }
        }
        
        # Look up Entry Type
        if ($entryTypeMapping.ContainsKey($alarmText)) {
            $entryType = $entryTypeMapping[$alarmText]
        } else {
            $entryType = $defaultEntryType
            if ($Test) {
                Write-Host "Warning: No Entry Type mapping found for '$alarmText', using default Entry Type $defaultEntryType" -ForegroundColor Yellow
            }
        }
        
        if ($Test) {
            # Display event log entry data in test mode
            $recordNumber = if ($columns.Count -gt 0) { $columns[0].Trim() } else { "Unknown" }

            # In test mode, show deduplication decision if enabled
            $wouldSkipAsDuplicate = $false
            if ($enableDeduplication) {
                $wouldSkipAsDuplicate = Test-EventHashExists -Hash $hashString -Source $eventSource -LookbackHours $deduplicationLookbackHours
            }
            Write-Host ""
            Write-Host ("="*80) -ForegroundColor Magenta
            Write-Host "Event Log Entry for record: $recordNumber" -ForegroundColor Cyan
            if ($wouldSkipAsDuplicate) {
                Write-Host "Decision      : SKIP (duplicate within last $deduplicationLookbackHours hour(s))" -ForegroundColor Yellow
            } else {
                Write-Host "Decision      : WRITE (no duplicate detected)" -ForegroundColor Green
            }
            Write-Host ("="*80) -ForegroundColor Magenta
            Write-Host "Log Name      : Application" -ForegroundColor White
            Write-Host "Source        : $eventSource" -ForegroundColor White
            Write-Host "Event ID      : $eventId" -ForegroundColor White
            Write-Host "Entry Type    : $entryType" -ForegroundColor White
            Write-Host "Time          : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
            Write-Host ""
            Write-Host "Message:" -ForegroundColor Yellow
            Write-Host $eventMessage -ForegroundColor Gray
            Write-Host ("="*80) -ForegroundColor Magenta
        } else {
            # Deduplication check before writing
            if ($enableDeduplication) {
                $isDuplicate = Test-EventHashExists -Hash $hashString -Source $eventSource -LookbackHours $deduplicationLookbackHours
                if ($isDuplicate) {
                    $recordNumber = if ($columns.Count -gt 0) { $columns[0].Trim() } else { "Unknown" }
                    Write-Host "Skipping duplicate event for record: $recordNumber (Hash: $hashString) within last $deduplicationLookbackHours hour(s)" -ForegroundColor Yellow
                    continue
                }
            }
            # Write to Windows Application event log
            Write-EventLog -LogName Application `
                          -Source $eventSource `
                          -EventId $eventId `
                          -EntryType $entryType `
                          -Message $eventMessage `
                          -ErrorAction Stop
            
            $recordNumber = if ($columns.Count -gt 0) { $columns[0].Trim() } else { "Unknown" }
            Write-Host "Successfully wrote event for record: $recordNumber with Event ID: $eventId and Entry Type: $entryType" -ForegroundColor Cyan
        }
        
    } catch {
        $recordNumber = if ($columns -and $columns.Count -gt 0) { $columns[0].Trim() } else { "Unknown" }
        Write-Error "Failed to process record: $recordNumber - $($_.Exception.Message)"
        continue
    }
}

Write-Host "`nProcessing complete!" -ForegroundColor Green

