param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$Path,

    [string]$OutSummaryCsv,
    [string]$OutPointCsv
)

$ErrorActionPreference = 'Stop'
$Invariant = [System.Globalization.CultureInfo]::InvariantCulture
$NearZeroRaw = 9
$WrongPositionRaw = 910
$RampPlateauTicks = 5
$StableWindowP2PRaw = $NearZeroRaw * 8
$ActiveCommandDeltaRaw = 3
$ActiveObservedNearZeroRaw = 2
$MajorBacktrackRaw = 18

function ConvertFrom-TraceLine {
    param([string]$Line)

    $fields = @{}
    $parts = $Line.Trim() -split ','
    $fields.RecordType = $parts[0].Trim()
    foreach ($part in $parts | Select-Object -Skip 1) {
        $separator = $part.IndexOf('=')
        if ($separator -le 0) { continue }
        $fields[$part.Substring(0, $separator).Trim()] =
            $part.Substring($separator + 1).Trim()
    }
    return $fields
}

function Convert-ToInt64 {
    param([object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value) `
            -or [string]$Value -eq 'NA') {
        return $null
    }
    return [int64]::Parse([string]$Value, $Invariant)
}

function Get-LongestNearZeroSequence {
    param([object[]]$Ramp)

    $longest = 0
    $current = 0
    $previousCommand = $null
    foreach ($sample in $Ramp) {
        $command = Convert-ToInt64 $sample.CommandRaw
        $delta = Convert-ToInt64 $sample.ObservedDeltaRaw
        $commandDelta = if ($null -ne $previousCommand -and $null -ne $command) {
            [Math]::Abs($command - $previousCommand)
        } else {
            0
        }
        # Ignore the deliberately flat head/tail of the quintic S-curve.
        # A possible stall requires the command itself to be actively moving
        # while the encoder makes almost no progress.
        if ($commandDelta -ge $ActiveCommandDeltaRaw -and
                $null -ne $delta -and
                [Math]::Abs($delta) -le $ActiveObservedNearZeroRaw) {
            $current++
            if ($current -gt $longest) { $longest = $current }
        } else {
            $current = 0
        }
        $previousCommand = $command
    }
    return $longest
}

$traces = @{}
foreach ($inputPath in $Path) {
    foreach ($resolved in @(Resolve-Path -Path $inputPath)) {
        $source = $resolved.Path
        foreach ($line in Get-Content -LiteralPath $source) {
            if ($line -notmatch '^\s*STUTTER_(?:TRACE_META|RAMP_STEP|SETTLE_SAMPLE),') {
                continue
            }
            $record = ConvertFrom-TraceLine $line
            $key = '{0}|{1}|{2}' -f $source, $record.TestID, $record.SweepID
            if (-not $traces.ContainsKey($key)) {
                $traces[$key] = [PSCustomObject]@{
                    Source = $source
                    TestID = $record.TestID
                    SweepID = $record.SweepID
                    Meta = $null
                    Ramp = [System.Collections.Generic.List[object]]::new()
                    Settle = [System.Collections.Generic.List[object]]::new()
                }
            }
            switch ($record.RecordType) {
                'STUTTER_TRACE_META' { $traces[$key].Meta = $record }
                'STUTTER_RAMP_STEP' { $traces[$key].Ramp.Add([PSCustomObject]$record) }
                'STUTTER_SETTLE_SAMPLE' { $traces[$key].Settle.Add([PSCustomObject]$record) }
            }
        }
    }
}

if ($traces.Count -eq 0) {
    throw 'No STUTTER_TRACE_META/STUTTER_RAMP_STEP/STUTTER_SETTLE_SAMPLE records found.'
}

$pointRows = @()
$summaryRows = @()
foreach ($trace in $traces.Values) {
    $points = @($trace.Ramp.Point + $trace.Settle.Point |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object { [int]$_ } -Unique)

    foreach ($pointText in $points) {
        $point = [int]$pointText
        $ramp = @($trace.Ramp | Where-Object { [int]$_.Point -eq $point } |
            Sort-Object { [int]$_.Tick })
        $settle = @($trace.Settle | Where-Object { [int]$_.Point -eq $point } |
            Sort-Object { [int]$_.Poll })

        $validRamp = @($ramp | Where-Object {
            $_.AcquisitionResult -eq 'OK' -and $_.ObservedRaw -ne 'NA'
        })
        $lags = @($validRamp | ForEach-Object { Convert-ToInt64 $_.LagRaw } |
            Where-Object { $null -ne $_ })
        $maxAbsLag = if ($lags.Count) {
            ($lags | ForEach-Object { [Math]::Abs($_) } |
                Measure-Object -Maximum).Maximum
        } else { $null }
        $rampEndLag = if ($validRamp.Count) {
            Convert-ToInt64 $validRamp[-1].LagRaw
        } else { $null }
        $rampEndObserved = if ($validRamp.Count) {
            Convert-ToInt64 $validRamp[-1].ObservedRaw
        } else { $null }

        $direction = if ($validRamp.Count) { $validRamp[0].Direction } else { 'CW' }
        $backtrackDeltas = @($validRamp | ForEach-Object {
            $delta = Convert-ToInt64 $_.ObservedDeltaRaw
            if ($null -eq $delta) { return }
            $isBacktrack = if ($direction -eq 'CCW') {
                $delta -gt $NearZeroRaw
            } else {
                $delta -lt -$NearZeroRaw
            }
            if ($isBacktrack) { $delta }
        })
        $maxBacktrack = if ($backtrackDeltas.Count) {
            ($backtrackDeltas | ForEach-Object { [Math]::Abs($_) } |
                Measure-Object -Maximum).Maximum
        } else { 0 }
        $majorBacktrackCount = @($backtrackDeltas | Where-Object {
            [Math]::Abs($_) -gt $MajorBacktrackRaw
        }).Count

        $lastSettle = if ($settle.Count) { $settle[-1] } else { $null }
        $finalObserved = if ($null -ne $lastSettle) {
            Convert-ToInt64 $lastSettle.ObservedRaw
        } else { $null }
        $settleCorrection = if ($null -ne $finalObserved -and
                $null -ne $rampEndObserved) {
            $finalObserved - $rampEndObserved
        } else { $null }
        $finalError = if ($null -ne $lastSettle) {
            Convert-ToInt64 $lastSettle.TargetErrorRaw
        } else { $null }
        $finalP2P = if ($null -ne $lastSettle) {
            Convert-ToInt64 $lastSettle.WindowP2PRaw
        } else { $null }
        $settleElapsed = if ($null -ne $lastSettle) {
            Convert-ToInt64 $lastSettle.ElapsedMs
        } else { $null }
        $settleResult = if ($null -ne $lastSettle) {
            $lastSettle.FinalSettleResult
        } else { 'INCOMPLETE' }
        $nearZeroSequence = Get-LongestNearZeroSequence $validRamp

        $classR = $nearZeroSequence -ge $RampPlateauTicks -or
            $majorBacktrackCount -gt 0
        $classE = $settleResult -eq 'WRONG_POSITION' -and
            $null -ne $finalError -and [Math]::Abs($finalError) -gt $WrongPositionRaw -and
            $null -ne $finalP2P -and $finalP2P -le $StableWindowP2PRaw
        $classS = -not $classR -and -not $classE -and
            $null -ne $settleElapsed -and $settleElapsed -ge 100 -and
            $null -ne $finalError -and [Math]::Abs($finalError) -gt $WrongPositionRaw
        $classification = if ($classR -and $classE) { 'MIXED' }
            elseif ($classR) { 'R' }
            elseif ($classE) { 'E' }
            elseif ($classS) { 'S' }
            else { 'NONE' }

        $pointRows += [PSCustomObject]@{
            Source = $trace.Source
            TestID = $trace.TestID
            SweepID = $trace.SweepID
            Point = $point
            RampSamples = $ramp.Count
            RampEndLagRaw = $rampEndLag
            MaxAbsLagRaw = $maxAbsLag
            LongestNearZeroTicks = $nearZeroSequence
            BacktrackCount = $backtrackDeltas.Count
            MaxBacktrackRaw = $maxBacktrack
            MajorBacktrackCount = $majorBacktrackCount
            SettlePolls = $settle.Count
            SettleElapsedMs = $settleElapsed
            SettleCorrectionRaw = $settleCorrection
            FinalTargetErrorRaw = $finalError
            FinalWindowP2PRaw = $finalP2P
            FinalSettleResult = $settleResult
            Classification = $classification
        }
    }

    $tracePoints = @($pointRows | Where-Object {
        $_.Source -eq $trace.Source -and $_.TestID -eq $trace.TestID -and
        $_.SweepID -eq $trace.SweepID
    })
    $summaryRows += [PSCustomObject]@{
        Source = $trace.Source
        TestID = $trace.TestID
        SweepID = $trace.SweepID
        Profile = if ($null -ne $trace.Meta) { $trace.Meta.Profile } else { '' }
        TraceStatus = if ($null -ne $trace.Meta) { $trace.Meta.Status } else { 'MISSING_META' }
        TraceComplete = if ($null -ne $trace.Meta) { $trace.Meta.Complete } else { '0' }
        PointCount = $tracePoints.Count
        RampRecordCount = $trace.Ramp.Count
        SettleRecordCount = $trace.Settle.Count
        WorstAbsLagRaw = ($tracePoints.MaxAbsLagRaw | Measure-Object -Maximum).Maximum
        LongestNearZeroTicks = ($tracePoints.LongestNearZeroTicks |
            Measure-Object -Maximum).Maximum
        TotalBacktracks = ($tracePoints.BacktrackCount | Measure-Object -Sum).Sum
        TotalMajorBacktracks = ($tracePoints.MajorBacktrackCount |
            Measure-Object -Sum).Sum
        MaxSettleElapsedMs = ($tracePoints.SettleElapsedMs |
            Measure-Object -Maximum).Maximum
        WrongPositionPoints = @($tracePoints |
            Where-Object FinalSettleResult -eq 'WRONG_POSITION').Count
        ClassRPoints = @($tracePoints | Where-Object Classification -in @('R', 'MIXED')).Count
        ClassEPoints = @($tracePoints | Where-Object Classification -in @('E', 'MIXED')).Count
        ClassSPoints = @($tracePoints | Where-Object Classification -eq 'S').Count
    }
}

$summaryRows | Sort-Object Source, TestID, SweepID

if ($OutSummaryCsv) {
    $summaryRows | Sort-Object Source, TestID, SweepID |
        Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $OutSummaryCsv
}
if ($OutPointCsv) {
    $pointRows | Sort-Object Source, TestID, SweepID, Point |
        Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $OutPointCsv
}
