# analyze_nonlinear_logs.ps1
# Parses raw jig console logs and extracts the nonlinear measurement fields used
# by docs/nonlinear-test-plan.md.

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$Path,

    [string]$OutCsv,

    [switch]$Summary
)

function Convert-ToNullableDouble {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    return [double]::Parse($Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-RegexValues {
    param(
        [string]$Text,
        [string]$Pattern
    )

    $matches = [regex]::Matches($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $values = @()
    foreach ($match in $matches) {
        $values += $match.Groups[1].Value
    }
    return $values
}

function Get-NumberedRegexValues {
    param(
        [string]$Text,
        [string]$Pattern
    )

    $table = @{}
    $matches = [regex]::Matches($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    foreach ($match in $matches) {
        $table[[int]$match.Groups[1].Value] = Convert-ToNullableDouble $match.Groups[2].Value
    }
    return $table
}

function Get-Mean {
    param([object[]]$Values)

    $numbers = @($Values | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if ($numbers.Count -eq 0) {
        return $null
    }

    return ($numbers | Measure-Object -Average).Average
}

function Round-Nullable {
    param(
        [object]$Value,
        [int]$Digits = 3
    )

    if ($null -eq $Value) {
        return $null
    }

    return [math]::Round([double]$Value, $Digits)
}

function Get-StdDev {
    param([object[]]$Values)

    $numbers = @($Values | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if ($numbers.Count -le 1) {
        return 0.0
    }

    $mean = Get-Mean $numbers
    $sum = 0.0
    foreach ($number in $numbers) {
        $sum += [math]::Pow($number - $mean, 2)
    }

    return [math]::Sqrt($sum / ($numbers.Count - 1))
}

function Get-SourceMetadata {
    param([string]$FilePath)

    $name = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $jig = ""
    $product = ""

    $jigMatch = [regex]::Match($name, '(?i)(?:^|[_\-\s])jig[_\-\s]*([A-Za-z0-9]+)')
    if ($jigMatch.Success) {
        $jig = $jigMatch.Groups[1].Value
    }

    if ($name -match '(?i)golden') {
        $product = "Golden"
    } else {
        $productMatch = [regex]::Match($name, '(?i)(?:^|[_\-\s])(?:product|prod|motor)[_\-\s]*([A-Za-z0-9]+)')
        if ($productMatch.Success) {
            $product = $productMatch.Groups[1].Value
        } else {
            $shortProductMatch = [regex]::Match($name, '(?i)(?:^|[_\-\s])p([0-9]+)(?:$|[_\-\s])')
            if ($shortProductMatch.Success) {
                $product = "P$($shortProductMatch.Groups[1].Value)"
            }
        }
    }

    return @{
        Jig = $jig
        Product = $product
    }
}

$records = @()

foreach ($inputPath in $Path) {
    $resolvedPaths = @(Resolve-Path -Path $inputPath -ErrorAction Stop)

    foreach ($resolvedPath in $resolvedPaths) {
        $file = $resolvedPath.Path
        $metadata = Get-SourceMetadata $file
        $text = Get-Content -Raw -Path $file
        $blocks = @([regex]::Split($text, '(?m)^\s*Getting result!\s*$') | Where-Object { $_ -match 'Nonlinear\s+\d+\s+Angle|Nonlinear Final Average' })
        $runIndex = 0

        foreach ($block in $blocks) {
            $runIndex++

            $offsets = @(Get-RegexValues $block '^\s*Motor offset:\s*(-?\d+)')
            $angleOffsets = @(Get-RegexValues $block '^\s*Motor angle offset:\s*(-?\d+(?:\.\d+)?)\s*degree')
            $ma600Modes = @(Get-RegexValues $block '^\s*MA600 diagnostic mode:\s+LUT\s+([A-Z]+)')
            $testCaseProduct = $null
            $testCaseRun = $null
            $testCaseMode = $null
            $lutCompareTcMatch = [regex]::Match($block, '^\s*LUT_COMPARE_TC\s+Mode\s+(\d+)\/(\d+)\s+([A-Z]+)', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $rawOffsetTcMatch = [regex]::Match($block, '^\s*RAW_OFFSET_TC\s+Product\s+(\d+)\/(\d+)\s+ExternalRun\s+(\d+)\/(\d+)\s+Mode=([A-Z]+)', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            if ($lutCompareTcMatch.Success) {
                $testCaseProduct = if ([string]::IsNullOrWhiteSpace($metadata.Product)) { "Product01" } else { $metadata.Product }
                $testCaseRun = [int]$lutCompareTcMatch.Groups[1].Value
                $testCaseMode = $lutCompareTcMatch.Groups[3].Value
            } elseif ($rawOffsetTcMatch.Success) {
                $testCaseProduct = "Product$($rawOffsetTcMatch.Groups[1].Value.PadLeft(2, '0'))"
                $testCaseRun = [int]$rawOffsetTcMatch.Groups[3].Value
                $testCaseMode = $rawOffsetTcMatch.Groups[5].Value
            } else {
                $legacyRawOffsetTcMatch = [regex]::Match($block, '^\s*RAW_OFFSET_TC\s+Product\s+P(\d+)\s+ExternalRun\s+(\d+)\/(\d+)\s+Mode=([A-Z]+)', [System.Text.RegularExpressions.RegexOptions]::Multiline)
                if ($legacyRawOffsetTcMatch.Success) {
                    $testCaseProduct = "Product$($legacyRawOffsetTcMatch.Groups[1].Value.PadLeft(2, '0'))"
                    $testCaseRun = [int]$legacyRawOffsetTcMatch.Groups[2].Value
                    $testCaseMode = $legacyRawOffsetTcMatch.Groups[4].Value
                }
            }
            $startDiagnostics = @([regex]::Matches($block, '^\s*MA600 start raw=(-?\d+)\s+count=(-?\d+)\s+filtered=(-?\d+(?:\.\d+)?)\s+rawAngle=(-?\d+(?:\.\d+)?)\s+degree', [System.Text.RegularExpressions.RegexOptions]::Multiline))
            $nlAngles = Get-NumberedRegexValues $block '^\s*Nonlinear\s+(\d+)\s+Angle:\s*(-?\d+(?:\.\d+)?)\s*degree'
            $rawNlAngles = Get-NumberedRegexValues $block '^\s*MA600 Raw Nonlinear\s+(\d+)\s+Angle:\s*(-?\d+(?:\.\d+)?)\s*degree'
            $filterRawDiffs = Get-NumberedRegexValues $block '^\s*MA600 Filter-Raw Max Diff\s+(\d+):\s*(-?\d+(?:\.\d+)?)\s*degree'

            $finalAverageMatch = [regex]::Match($block, '^\s*Nonlinear Final Average:\s*(-?\d+(?:\.\d+)?)\s*degree', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $rawFinalAverageMatch = [regex]::Match($block, '^\s*MA600 Raw Nonlinear Final Average:\s*(-?\d+(?:\.\d+)?)\s*degree', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $powerMatch = [regex]::Match($block, '^\s*Power min CW:\s*(-?\d+(?:\.\d+)?)%', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $resultMatch = [regex]::Match($block, '^\s*Motor\s+(OK|ERROR:\s*[^!\r\n]+!?)', [System.Text.RegularExpressions.RegexOptions]::Multiline)

            $motorOffset1 = if ($offsets.Count -ge 1) { [int]$offsets[0] } else { $null }
            $motorOffset2 = if ($offsets.Count -ge 2) { [int]$offsets[1] } else { $null }
            $motorOffset3 = if ($offsets.Count -ge 3) { [int]$offsets[2] } else { $null }

            $angleOffset1 = if ($angleOffsets.Count -ge 1) { Convert-ToNullableDouble $angleOffsets[0] } else { $null }
            $angleOffset2 = if ($angleOffsets.Count -ge 2) { Convert-ToNullableDouble $angleOffsets[1] } else { $null }
            $angleOffset3 = if ($angleOffsets.Count -ge 3) { Convert-ToNullableDouble $angleOffsets[2] } else { $null }

            $startRaw = @()
            $startCount = @()
            $startFiltered = @()
            $startRawAngle = @()
            foreach ($diag in $startDiagnostics) {
                $startRaw += [int]$diag.Groups[1].Value
                $startCount += [int]$diag.Groups[2].Value
                $startFiltered += Convert-ToNullableDouble $diag.Groups[3].Value
                $startRawAngle += Convert-ToNullableDouble $diag.Groups[4].Value
            }

            $nlAvg = if ($finalAverageMatch.Success) { Convert-ToNullableDouble $finalAverageMatch.Groups[1].Value } else { Get-Mean @($nlAngles[2], $nlAngles[3]) }
            $rawNlAvg = if ($rawFinalAverageMatch.Success) { Convert-ToNullableDouble $rawFinalAverageMatch.Groups[1].Value } else { Get-Mean @($rawNlAngles[2], $rawNlAngles[3]) }
            $recordProduct = if ($null -ne $testCaseProduct) { $testCaseProduct } else { $metadata.Product }
            $recordRun = if ($null -ne $testCaseRun) { $testCaseRun } else { $runIndex }
            $recordMode = if ($null -ne $testCaseMode) { $testCaseMode } elseif ($ma600Modes.Count -gt 0) { $ma600Modes[0] } else { "" }

            $record = [pscustomobject]@{
                Source = [System.IO.Path]::GetFileName($file)
                Jig = $metadata.Jig
                Product = $recordProduct
                Run = $recordRun
                MA600Mode = $recordMode
                MotorOffset1 = $motorOffset1
                MotorOffset2 = $motorOffset2
                MotorOffset3 = $motorOffset3
                MotorOffsetUsedMean = Get-Mean @($motorOffset2, $motorOffset3)
                AngleOffset1 = $angleOffset1
                AngleOffset2 = $angleOffset2
                AngleOffset3 = $angleOffset3
                AngleOffsetUsedMean = Get-Mean @($angleOffset2, $angleOffset3)
                StartRaw1 = if ($startRaw.Count -ge 1) { $startRaw[0] } else { $null }
                StartRaw2 = if ($startRaw.Count -ge 2) { $startRaw[1] } else { $null }
                StartRaw3 = if ($startRaw.Count -ge 3) { $startRaw[2] } else { $null }
                StartRawUsedMean = Get-Mean @(
                    $(if ($startRaw.Count -ge 2) { $startRaw[1] } else { $null }),
                    $(if ($startRaw.Count -ge 3) { $startRaw[2] } else { $null })
                )
                StartCount1 = if ($startCount.Count -ge 1) { $startCount[0] } else { $null }
                StartCount2 = if ($startCount.Count -ge 2) { $startCount[1] } else { $null }
                StartCount3 = if ($startCount.Count -ge 3) { $startCount[2] } else { $null }
                StartCountUsedMean = Get-Mean @(
                    $(if ($startCount.Count -ge 2) { $startCount[1] } else { $null }),
                    $(if ($startCount.Count -ge 3) { $startCount[2] } else { $null })
                )
                StartFilteredUsedMean = Get-Mean @(
                    $(if ($startFiltered.Count -ge 2) { $startFiltered[1] } else { $null }),
                    $(if ($startFiltered.Count -ge 3) { $startFiltered[2] } else { $null })
                )
                StartRawAngleUsedMean = Get-Mean @(
                    $(if ($startRawAngle.Count -ge 2) { $startRawAngle[1] } else { $null }),
                    $(if ($startRawAngle.Count -ge 3) { $startRawAngle[2] } else { $null })
                )
                NL1 = $nlAngles[1]
                NL2 = $nlAngles[2]
                NL3 = $nlAngles[3]
                NLAvg = $nlAvg
                RawNL1 = $rawNlAngles[1]
                RawNL2 = $rawNlAngles[2]
                RawNL3 = $rawNlAngles[3]
                RawNLAvg = $rawNlAvg
                NLMinusRawAvg = if (($null -ne $nlAvg) -and ($null -ne $rawNlAvg)) { $nlAvg - $rawNlAvg } else { $null }
                FilterRawDiff2 = $filterRawDiffs[2]
                FilterRawDiff3 = $filterRawDiffs[3]
                FilterRawDiffUsedMax = (@($filterRawDiffs[2], $filterRawDiffs[3]) | Where-Object { $null -ne $_ } | Measure-Object -Maximum).Maximum
                PowerMinCW = if ($powerMatch.Success) { Convert-ToNullableDouble $powerMatch.Groups[1].Value } else { $null }
                Result = if ($resultMatch.Success) { $resultMatch.Groups[1].Value.Trim() } else { "" }
            }

            $records += $record
        }
    }
}

if ($records.Count -eq 0) {
    Write-Host "[FAIL] No nonlinear result blocks found."
    exit 1
}

$records |
    Sort-Object Source, Run |
    Format-Table Source, Jig, Product, Run, MA600Mode, NLAvg, RawNLAvg, NLMinusRawAvg, MotorOffsetUsedMean, AngleOffsetUsedMean, StartRawUsedMean -AutoSize

if ($OutCsv) {
    $outDir = Split-Path -Parent $OutCsv
    if ($outDir -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir | Out-Null
    }

    $records | Sort-Object Source, Run | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutCsv
    Write-Host ""
    Write-Host "[ OK ] CSV written: $OutCsv"
}

if ($Summary) {
    Write-Host ""
    Write-Host "== Summary by Jig/Product =="

    $records |
        Group-Object Jig, Product, MA600Mode |
        ForEach-Object {
            $values = @($_.Group | ForEach-Object { $_.NLAvg } | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
            $rawValues = @($_.Group | ForEach-Object { $_.RawNLAvg } | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
            $offsetValues = @($_.Group | ForEach-Object { $_.MotorOffsetUsedMean } | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
            $nlMinusRawValues = @($_.Group | ForEach-Object { $_.NLMinusRawAvg } | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
            $min = if ($values.Count -gt 0) { ($values | Measure-Object -Minimum).Minimum } else { $null }
            $max = if ($values.Count -gt 0) { ($values | Measure-Object -Maximum).Maximum } else { $null }
            $rawMin = if ($rawValues.Count -gt 0) { ($rawValues | Measure-Object -Minimum).Minimum } else { $null }
            $rawMax = if ($rawValues.Count -gt 0) { ($rawValues | Measure-Object -Maximum).Maximum } else { $null }
            $offsetMin = if ($offsetValues.Count -gt 0) { ($offsetValues | Measure-Object -Minimum).Minimum } else { $null }
            $offsetMax = if ($offsetValues.Count -gt 0) { ($offsetValues | Measure-Object -Maximum).Maximum } else { $null }

            [pscustomobject]@{
                Jig = $_.Group[0].Jig
                Product = $_.Group[0].Product
                MA600Mode = $_.Group[0].MA600Mode
                Count = $_.Count
                NLAvgMean = Round-Nullable (Get-Mean $values)
                NLAvgRange = if (($null -ne $min) -and ($null -ne $max)) { Round-Nullable ($max - $min) } else { $null }
                NLAvgStdDev = Round-Nullable (Get-StdDev $values)
                RawNLAvgMean = Round-Nullable (Get-Mean $rawValues)
                RawNLAvgRange = if (($null -ne $rawMin) -and ($null -ne $rawMax)) { Round-Nullable ($rawMax - $rawMin) } else { $null }
                NLMinusRawMean = Round-Nullable (Get-Mean $nlMinusRawValues)
                MotorOffsetRange = if (($null -ne $offsetMin) -and ($null -ne $offsetMax)) { Round-Nullable ($offsetMax - $offsetMin) } else { $null }
            }
        } |
        Sort-Object Product, Jig, MA600Mode |
        Format-Table -AutoSize
}
