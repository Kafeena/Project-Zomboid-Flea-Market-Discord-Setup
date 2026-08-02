$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PrivateDirectory = Join-Path $env:USERPROFILE 'Zomboid\Lua\KafeenaFleaMarketBridge'
$ConfigPath = Join-Path $PrivateDirectory 'discord_private.json'
$StatePath = Join-Path $PrivateDirectory 'discord_bridge_state.json'
$DefaultAuditPath = Join-Path $env:USERPROFILE 'Zomboid\Lua\KafeenaFleaMarket_Audit.log'
$LegacyQueueFileNames = @('KafeenaFleaMarket_DiscordQueue.jsonl', 'KafeenaFleaMarket_DiscordQueue.txt')

function Write-Header {
    Clear-Host
    Write-Host '============================================================' -ForegroundColor DarkRed
    Write-Host ' Flea Market by Kafeena - Discord Bridge' -ForegroundColor White
    Write-Host '============================================================' -ForegroundColor DarkRed
    Write-Host
}

function Stop-WithMessage {
    param([string]$Message)
    Write-Host
    Write-Host $Message -ForegroundColor Red
    Write-Host
    Read-Host 'Press ENTER to close' | Out-Null
    exit 1
}

function Save-JsonFile {
    param($Object, [string]$Path)
    $Parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $Parent)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }
    $Object | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Test-WebhookUrl {
    param([string]$Url)
    return $Url -match '^https://(canary\.|ptb\.)?(discord|discordapp)\.com/api/webhooks/[0-9]+/[A-Za-z0-9._-]+$'
}

function Send-WebhookPayload {
    param([string]$WebhookUrl, $Payload)
    $Body = $Payload | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Uri ($WebhookUrl + '?wait=true') -Method Post -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($Body)) | Out-Null
}

function New-PrivateSetup {
    Write-Header
    Write-Host 'First-time setup. The game writes plain-text audit events.' -ForegroundColor Cyan
    Write-Host 'Only this external bridge converts them into Discord messages.' -ForegroundColor Gray
    Write-Host

    $WebhookUrl = (Read-Host 'Paste the NEW Discord webhook URL').Trim()
    if (-not (Test-WebhookUrl $WebhookUrl)) {
        Stop-WithMessage 'That does not look like a valid Discord webhook URL.'
    }

    $ServerName = (Read-Host 'Server name shown in Discord [Project Zomboid]').Trim()
    if ([string]::IsNullOrWhiteSpace($ServerName)) { $ServerName = 'Project Zomboid' }

    $RoleId = (Read-Host 'Optional Discord role ID to mention [leave blank]').Trim()
    if ($RoleId -and $RoleId -notmatch '^[0-9]+$') {
        Write-Host 'Role ID was not numeric, so role mentions were disabled.' -ForegroundColor Yellow
        $RoleId = ''
    }

    Write-Host
    Write-Host "Default audit log: $DefaultAuditPath" -ForegroundColor Gray
    $AuditPath = (Read-Host 'Press ENTER for default, or paste a different full audit-log path').Trim()
    if ([string]::IsNullOrWhiteSpace($AuditPath)) { $AuditPath = $DefaultAuditPath }

    $Config = [ordered]@{
        webhook_url = $WebhookUrl
        queue_file = $AuditPath
        poll_seconds = 2
        server_name = $ServerName
        mention_role_id = $RoleId
        send_events = @('listed','sold','promoted','cancelled','expired','admin_removed','test')
    }
    Save-JsonFile -Object $Config -Path $ConfigPath

    $TestPayload = [ordered]@{
        allowed_mentions = [ordered]@{ parse = @() }
        embeds = @([ordered]@{
            title = 'Flea Market Discord Bridge Connected'
            description = 'The bridge is connected. It will watch the plain-text flea-market audit log for new market events.'
            color = 11819589
            footer = [ordered]@{ text = "$ServerName - Flea Market by Kafeena" }
            timestamp = [DateTime]::UtcNow.ToString('o')
        })
    }

    try {
        Send-WebhookPayload -WebhookUrl $WebhookUrl -Payload $TestPayload
        Write-Host
        Write-Host 'Setup saved. A connection test was posted to Discord.' -ForegroundColor Green
        Start-Sleep -Seconds 2
    }
    catch {
        Remove-Item -LiteralPath $ConfigPath -Force -ErrorAction SilentlyContinue
        Stop-WithMessage "Discord rejected the test or the connection failed: $($_.Exception.Message)"
    }
}

function Url-Decode {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    try { return [Uri]::UnescapeDataString($Value) }
    catch { return $Value }
}

function Parse-Details {
    param([string]$Text)
    $Result = @{}
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Result }
    foreach ($Pair in ($Text -split '&')) {
        if ([string]::IsNullOrWhiteSpace($Pair)) { continue }
        $Parts = $Pair -split '=', 2
        $Key = Url-Decode $Parts[0]
        $Value = ''
        if ($Parts.Count -gt 1) { $Value = Url-Decode $Parts[1] }
        $Result[$Key] = $Value
    }
    return $Result
}

function Convert-AuditLineToEvent {
    param([string]$Line)
    $Match = [regex]::Match($Line, '^(.*?)\s*\|\s*([A-Z0-9_]+)\s*\|\s*(.*?)\s*\|\s*(.*)$')
    if (-not $Match.Success) { return $null }

    $AuditEvent = $Match.Groups[2].Value.Trim()
    if (-not $AuditEvent.StartsWith('DISCORD_')) { return $null }

    $EventName = $AuditEvent.Substring(8).ToLowerInvariant()
    $Actor = $Match.Groups[3].Value.Trim()
    $Values = Parse-Details $Match.Groups[4].Value

    $Price = 0
    if ($Values.ContainsKey('price')) { [void][int]::TryParse([string]$Values['price'], [ref]$Price) }
    $Condition = -1
    if ($Values.ContainsKey('condition')) { [void][int]::TryParse([string]$Values['condition'], [ref]$Condition) }
    $Hours = 0
    if ($Values.ContainsKey('hours')) { [void][int]::TryParse([string]$Values['hours'], [ref]$Hours) }

    $Timestamp = $Match.Groups[1].Value.Trim()
    if ($Values.ContainsKey('timestamp') -and -not [string]::IsNullOrWhiteSpace([string]$Values['timestamp'])) {
        $Timestamp = [string]$Values['timestamp']
    }

    return [pscustomobject]@{
        event = $EventName
        listingId = [string]$Values['listingId']
        item = [string]$Values['item']
        fullType = [string]$Values['fullType']
        price = $Price
        condition = $Condition
        seller = $(if ($Values.ContainsKey('seller')) { [string]$Values['seller'] } else { $Actor })
        buyer = [string]$Values['buyer']
        moderator = [string]$Values['moderator']
        note = [string]$Values['note']
        hours = $Hours
        timestamp = $Timestamp
    }
}

function Get-EventTitle {
    param([string]$EventName)
    switch ($EventName) {
        'listed'        { return 'New Flea Market Listing' }
        'sold'          { return 'Flea Market Item Sold' }
        'promoted'      { return "What's Hot Promotion" }
        'cancelled'     { return 'Flea Market Listing Cancelled' }
        'expired'       { return 'Flea Market Listing Expired' }
        'admin_removed' { return 'Flea Market Listing Removed by Admin' }
        'test'          { return 'Flea Market Bridge Test' }
        default         { return 'Flea Market Event' }
    }
}

function Get-EventColor {
    param([string]$EventName)
    switch ($EventName) {
        'listed'        { return 11819589 }
        'sold'          { return 5151336 }
        'promoted'      { return 13936428 }
        'cancelled'     { return 7829367 }
        'expired'       { return 10910779 }
        'admin_removed' { return 10172986 }
        'test'          { return 5151336 }
        default         { return 11819589 }
    }
}

function Limit-DiscordText {
    param($Value, [int]$Maximum = 1024)
    $Text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($Text)) { return 'None' }
    if ($Text.Length -gt $Maximum) { return $Text.Substring(0, $Maximum) }
    return $Text
}

function Convert-EventToPayload {
    param($Event, $Config)
    $EventName = ([string]$Event.event).ToLowerInvariant()
    $Fields = New-Object System.Collections.ArrayList

    if (-not [string]::IsNullOrWhiteSpace([string]$Event.item)) {
        [void]$Fields.Add([ordered]@{ name='Item'; value=(Limit-DiscordText $Event.item); inline=$true })
    }
    [void]$Fields.Add([ordered]@{ name='Price'; value=('$' + ([int]$Event.price).ToString('N0')); inline=$true })
    if ([int]$Event.condition -ge 0) {
        [void]$Fields.Add([ordered]@{ name='Condition'; value=(([int]$Event.condition).ToString() + '%'); inline=$true })
    }
    [void]$Fields.Add([ordered]@{ name='Seller'; value=(Limit-DiscordText $Event.seller); inline=$true })
    [void]$Fields.Add([ordered]@{ name='Listing'; value=(Limit-DiscordText $Event.listingId); inline=$true })
    if ([int]$Event.hours -gt 0) {
        [void]$Fields.Add([ordered]@{ name='Duration'; value=(([int]$Event.hours).ToString() + ' in-game hours'); inline=$true })
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Event.buyer)) {
        [void]$Fields.Add([ordered]@{ name='Buyer'; value=(Limit-DiscordText $Event.buyer); inline=$true })
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Event.moderator)) {
        [void]$Fields.Add([ordered]@{ name='Moderator'; value=(Limit-DiscordText $Event.moderator); inline=$true })
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Event.note)) {
        [void]$Fields.Add([ordered]@{ name='Seller Note'; value=(Limit-DiscordText $Event.note); inline=$false })
    }

    $RoleId = ([string]$Config.mention_role_id).Trim()
    $MentionEvent = $EventName -eq 'listed' -or $EventName -eq 'promoted'
    $Content = ''
    $AllowedMentions = [ordered]@{ parse = @() }
    if ($RoleId -match '^[0-9]+$' -and $MentionEvent) {
        $Content = "<@&$RoleId>"
        $AllowedMentions = [ordered]@{ roles = @($RoleId); parse = @() }
    }

    $Timestamp = [string]$Event.timestamp
    if ([string]::IsNullOrWhiteSpace($Timestamp)) { $Timestamp = [DateTime]::UtcNow.ToString('o') }

    return [ordered]@{
        content = $Content
        allowed_mentions = $AllowedMentions
        embeds = @([ordered]@{
            title = (Get-EventTitle $EventName)
            color = (Get-EventColor $EventName)
            fields = @($Fields)
            footer = [ordered]@{ text = "$($Config.server_name) - Flea Market by Kafeena" }
            timestamp = $Timestamp
        })
    }
}

try {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { New-PrivateSetup }

    $Config = Read-JsonFile -Path $ConfigPath
    if (-not (Test-WebhookUrl ([string]$Config.webhook_url))) {
        Stop-WithMessage 'Saved webhook is missing or invalid. Run RESET_DISCORD_SETUP.bat, then start again.'
    }

    $AuditPath = [Environment]::ExpandEnvironmentVariables([string]$Config.queue_file)
    if ([string]::IsNullOrWhiteSpace($AuditPath)) { $AuditPath = $DefaultAuditPath }
    $ConfiguredLeaf = Split-Path -Leaf $AuditPath
    if ($LegacyQueueFileNames -contains $ConfiguredLeaf) {
        $AuditPath = $DefaultAuditPath
        $Config.queue_file = $DefaultAuditPath
        Save-JsonFile -Object $Config -Path $ConfigPath
    }

    $PollSeconds = 2
    if ($Config.poll_seconds) { $PollSeconds = [Math]::Max(1, [int]$Config.poll_seconds) }
    $EnabledEvents = @($Config.send_events | ForEach-Object { ([string]$_).ToLowerInvariant() })

    $ProcessedLines = 0
    if (Test-Path -LiteralPath $StatePath) {
        try {
            $State = Read-JsonFile -Path $StatePath
            $ProcessedLines = [Math]::Max(0, [int]$State.processed_lines)
        }
        catch { $ProcessedLines = 0 }
    }

    Write-Header
    Write-Host "Server: $($Config.server_name)" -ForegroundColor White
    Write-Host "Watching plain-text audit log: $AuditPath" -ForegroundColor Cyan
    Write-Host 'Keep this window open while the Project Zomboid server is running.' -ForegroundColor Yellow
    Write-Host 'Press CTRL+C to stop the bridge.' -ForegroundColor Gray
    Write-Host

    while ($true) {
        try {
            if (Test-Path -LiteralPath $AuditPath) {
                $Lines = @(Get-Content -LiteralPath $AuditPath -Encoding UTF8 -ErrorAction Stop)
                if ($ProcessedLines -gt $Lines.Count) { $ProcessedLines = 0 }

                for ($Index = $ProcessedLines; $Index -lt $Lines.Count; $Index++) {
                    $Line = ([string]$Lines[$Index]).Trim()
                    $Event = Convert-AuditLineToEvent $Line
                    if ($null -ne $Event) {
                        $EventName = ([string]$Event.event).ToLowerInvariant()
                        if ($EventName -eq 'test' -or $EnabledEvents -contains $EventName) {
                            $Payload = Convert-EventToPayload -Event $Event -Config $Config
                            Send-WebhookPayload -WebhookUrl ([string]$Config.webhook_url) -Payload $Payload
                            Write-Host ("[{0}] Sent {1} {2}" -f (Get-Date -Format 'HH:mm:ss'), $EventName, [string]$Event.listingId) -ForegroundColor Green
                        }
                    }
                    $ProcessedLines = $Index + 1
                    Save-JsonFile -Object ([ordered]@{ processed_lines=$ProcessedLines }) -Path $StatePath
                }
            }
        }
        catch {
            Write-Host ("[{0}] Bridge warning: {1}" -f (Get-Date -Format 'HH:mm:ss'), $_.Exception.Message) -ForegroundColor Red
            Write-Host 'The newest event was not discarded. The bridge will retry.' -ForegroundColor DarkYellow
        }
        Start-Sleep -Seconds $PollSeconds
    }
}
catch {
    Stop-WithMessage "Bridge stopped: $($_.Exception.Message)"
}
