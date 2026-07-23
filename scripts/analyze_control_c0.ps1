param(
    [Parameter(Mandatory = $true)]
    [string]$LogPath,
    [string]$CsvPath
)

$ErrorActionPreference = 'Stop'

function Convert-ControlRecord {
    param([string]$Line)
    $fields = $Line.Trim() -split ','
    if ($fields.Count -lt 1) { return $null }
    $record = [ordered]@{ RecordType = $fields[0] }
    for ($i = 1; $i -lt $fields.Count; $i++) {
        $separator = $fields[$i].IndexOf('=')
        if ($separator -le 0) { continue }
        $key = $fields[$i].Substring(0, $separator)
        $value = $fields[$i].Substring($separator + 1)
        $record[$key] = $value
    }
    return [pscustomobject]$record
}

function Read-Int64Field {
    param([object]$Record, [string]$Name)
    $property = $Record.PSObject.Properties[$Name]
    if ($null -eq $property) { throw "Missing $Name in $($Record.RecordType)." }
    return [int64]$property.Value
}

if (-not (Test-Path -LiteralPath $LogPath)) {
    throw "Control log not found: $LogPath"
}

$records = Get-Content -LiteralPath $LogPath | Where-Object {
    $_ -match '^CONTROL_C0_(SUMMARY|HEALTH|DATA|RUNTIME),'
} | ForEach-Object { Convert-ControlRecord $_ }

$summary = $records | Where-Object RecordType -eq 'CONTROL_C0_SUMMARY' |
    Select-Object -Last 1
$health = $records | Where-Object RecordType -eq 'CONTROL_C0_HEALTH' |
    Select-Object -Last 1
$runtime = $records | Where-Object RecordType -eq 'CONTROL_C0_RUNTIME' |
    Select-Object -Last 1
$rawData = @($records | Where-Object RecordType -eq 'CONTROL_C0_DATA')
if ($null -eq $summary -or $null -eq $health -or $rawData.Count -eq 0) {
    throw 'Log is missing CONTROL_C0_SUMMARY, CONTROL_C0_HEALTH, or DATA records.'
}

$data = @($rawData | ForEach-Object {
    [pscustomobject]@{
        Seq = Read-Int64Field $_ 'Seq'
        Phase = $_.Phase
        ReferenceMilliDeg = Read-Int64Field $_ 'ReferenceMilliDeg'
        ActualMilliDeg = Read-Int64Field $_ 'ActualMilliDeg'
        ErrorMilliDeg = Read-Int64Field $_ 'ErrorMilliDeg'
        VelocityRawPerSecond = Read-Int64Field $_ 'VelocityRawPerSecond'
        AccelerationRawPerSecond2 = Read-Int64Field $_ 'AccelerationRawPerSecond2'
        LoopCycles = Read-Int64Field $_ 'LoopCycles'
        SpiLatencyCycles = Read-Int64Field $_ 'SpiLatencyCycles'
        LatenessTicks = Read-Int64Field $_ 'LatenessTicks'
        CorrectionRaw = Read-Int64Field $_ 'CorrectionRaw'
    }
})

if ($data | Where-Object CorrectionRaw -ne 0) {
    throw 'C0 log contains non-zero correction and is not an open-loop data set.'
}

$hold = @($data | Where-Object Phase -eq 'HOLD')
if ($hold.Count -eq 0) { throw 'C0 log contains no HOLD evidence.' }
$rmsError = [math]::Sqrt((($hold | ForEach-Object {
    [double]$_.ErrorMilliDeg * [double]$_.ErrorMilliDeg
} | Measure-Object -Average).Average))
$maxAbsError = ($hold | ForEach-Object {
    [math]::Abs([double]$_.ErrorMilliDeg)
} | Measure-Object -Maximum).Maximum
$maxActual = ($data.ActualMilliDeg | Measure-Object -Maximum).Maximum
$overshoot = [math]::Max(0.0, [double]$maxActual - 1000.0)
$rise = $data | Where-Object ActualMilliDeg -ge 900 | Select-Object -First 1
$lastOutside = $hold | Where-Object {
    [math]::Abs([double]$_.ErrorMilliDeg) -gt 100.0
} | Select-Object -Last 1
$settle = if ($null -eq $lastOutside) {
    $hold | Select-Object -First 1
} else {
    $hold | Where-Object Seq -gt $lastOutside.Seq | Select-Object -First 1
}
$maxLoopCycles = ($data.LoopCycles | Measure-Object -Maximum).Maximum
$maxSpiCycles = ($data.SpiLatencyCycles | Measure-Object -Maximum).Maximum

$analysis = [pscustomobject]@{
    Profile = $summary.Profile
    Result = $summary.Result
    EvidenceCount = $data.Count
    HoldCount = $hold.Count
    FinalActualMilliDeg = $data[-1].ActualMilliDeg
    FinalErrorMilliDeg = $data[-1].ErrorMilliDeg
    HoldRmsErrorMilliDeg = [math]::Round($rmsError, 3)
    HoldMaxAbsErrorMilliDeg = [math]::Round($maxAbsError, 3)
    OvershootMilliDeg = [math]::Round($overshoot, 3)
    Rise90Sequence = if ($null -eq $rise) { 'NA' } else { $rise.Seq }
    Settle100mdegSequence = if ($null -eq $settle) { 'NA' } else { $settle.Seq }
    MaxLoopCycles = $maxLoopCycles
    MaxLoopUsAt168MHz = [math]::Round([double]$maxLoopCycles / 168.0, 3)
    MaxSpiLatencyCycles = $maxSpiCycles
    MaxSpiLatencyUsAt168MHz = [math]::Round([double]$maxSpiCycles / 168.0, 3)
    DeadlineMisses = $health.DeadlineMisses
    TransportErrors = $health.TransportErrors
    JumpRejects = $health.JumpRejects
    FailedSamples = $health.FailedSamples
    FreeHeap = if ($null -eq $runtime) { 'NA' } else { $runtime.FreeHeap }
    MinEverFreeHeap = if ($null -eq $runtime) { 'NA' } else { $runtime.MinEverFreeHeap }
    ControlStackHighWaterWords = if ($null -eq $runtime) {
        'NA'
    } else {
        $runtime.ControlStackHighWaterWords
    }
}

if ($CsvPath) {
    $data | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding utf8
    Write-Host "[ OK ] C0 evidence CSV written: $CsvPath"
}

Write-Output $analysis
