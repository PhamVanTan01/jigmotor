$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$log = Join-Path $env:TEMP 'jigmotor-control-a2-analyzer.log'
$multiLog = Join-Path $env:TEMP 'jigmotor-control-a2-analyzer-multi.log'
$csv = Join-Path $env:TEMP 'jigmotor-control-a2-analyzer.csv'
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('CONTROL_A2_ARMED,Profile=CONTROL_A2B_FIXED_PHASE_ALIGN_P10_H500_V1,CommandPhaseRaw=0,TargetPowerMilli=100,RampMs=500,HoldMs=500,PeriodMs=1,MaxTravelMilliDeg=5000,MaxStepMilliDeg=250,CorrectionRaw=0')
$lines.Add('CONTROL_A2_SUMMARY,Profile=CONTROL_A2B_FIXED_PHASE_ALIGN_P10_H500_V1,Result=OK,CommandPhaseRaw=0,TargetPowerMilli=100,RampMs=500,HoldMs=500,ActiveDurationMs=1000,EvidenceCount=1001,BaselineRaw=1000,FinalRaw=1006,MaxTravelMilliDeg=33,MaxStepMilliDeg=5')
$lines.Add('CONTROL_A2_SEQUENCE,PrimeStateValid=1,EnableStateValid=1,EnablePowerPpm=0')
$lines.Add('CONTROL_A2_HEALTH,DeadlineMisses=0,MaxLatenessTicks=0,MaxLoopCycles=3002,MaxAbsVelocityRawPerSecond=1000,AccelerationSaturations=0,ReadAttempts=1002,Accepted=1002,Retries=0,TransportErrors=0,JumpRejects=0,FailedSamples=0')

$previousVelocity = 0
for ($seq = 0; $seq -le 1000; $seq++) {
    $travel = [math]::Min(6, [math]::Floor($seq / 100))
    $previousTravel = if ($seq -eq 0) { 0 } else { [math]::Min(6, [math]::Floor(($seq - 1) / 100)) }
    $delta = $travel - $previousTravel
    $velocity = $delta * 1000
    $acceleration = ($velocity - $previousVelocity) * 1000
    $previousVelocity = $velocity
    $phase = if ($seq -le 500) { 'ALIGN_RAMP' } else { 'ALIGN_HOLD' }
    $power = if ($seq -ge 500) { 100000 } else { $seq * 200 }
    $travelMilli = [math]::Round($travel * 360000.0 / 65536.0)
    $lines.Add("CONTROL_A2_DATA,Seq=$seq,Phase=$phase,EncoderRaw=$($travel + 1000),TravelMilliDeg=$travelMilli,DeltaRaw=$delta,VelocityRawPerSecond=$velocity,AccelerationRawPerSecond2=$acceleration,CommandPhaseRaw=0,PowerPpm=$power,ScheduledTick=$($seq + 1000),SampleTick=$($seq + 1000),LatenessTicks=0,LoopCycles=$($seq % 3 + 3000),SpiLatencyCycles=1336,PwmCounterAtCs=10,CorrectionRaw=0")
}
$lines.Add('CONTROL_A2_RUNTIME,FreeHeap=90000,MinEverFreeHeap=89000,ControlStackHighWaterWords=1100')
$lines | Set-Content -LiteralPath $log -Encoding ascii

$analysis = & (Join-Path $PSScriptRoot 'analyze_control_a2.ps1') `
    -LogPath $log -SummaryCsv $csv
Assert-True $analysis.GatePass 'Synthetic valid A2B run did not pass.'
Assert-True ($analysis.EvidenceCount -eq 1001 -and $analysis.BaselineRaw -eq 1000 -and
    $analysis.FinalRaw -eq 1006) 'A2B identity/evidence parsing failed.'
Assert-True ($analysis.MaxAbsStepRaw -eq 1 -and $analysis.SpiMeanUs -eq 7.952) `
    'A2B motion or SPI metric calculation failed.'
Assert-True ($analysis.HoldP2PMilliDeg -gt 5.4 -and
    $analysis.HoldP2PMilliDeg -lt 5.6) 'A2B hold calculation failed.'
Assert-True ((Test-Path -LiteralPath $csv) -and
    @(Import-Csv -LiteralPath $csv).Count -eq 1) 'A2B summary CSV export failed.'

@($lines) + @($lines) | Set-Content -LiteralPath $multiLog -Encoding ascii
$multi = @(& (Join-Path $PSScriptRoot 'analyze_control_a2.ps1') -LogPath $multiLog)
Assert-True ($multi.Count -eq 2 -and $multi[0].Run -match '#1$' -and
    $multi[1].Run -match '#2$' -and $multi[0].GatePass -and $multi[1].GatePass) `
    'A2B analyzer failed to split multiple ARMED blocks in one file.'

Write-Host '[ OK ] Control A2/A2B analyzer regression test passed.'
