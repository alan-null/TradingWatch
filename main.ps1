# Prerequisites
# Install-Module -Name BurntToast

function Merge-Tokens($template, $tokens) {
    return [regex]::Replace($template, '\$(?<token>\w+)\$',
        { param($match) $tokens[$match.Groups['token'].Value] })
}

function Update-State($conf) {
    if ($conf.occurrence -eq "once") {
        $conf.state = "disabled"
    }
}

function Write-Message {
    param (
        [string[]]$template,
        $tokens
    )
    $messages = $template | % { Merge-Tokens $_  $tokens }
    New-BurntToastNotification -Text $messages -Sound 'Default' -SnoozeAndDismiss
}

function Get-Stats {
    param ()
    $stats = Invoke-WebRequest -Uri "https://www.bitstamp.net/api/v2/ticker/btcusd" -Method Get | ConvertFrom-Json
    $stats
}

$config = Get-ChildItem $PSScriptRoot -Filter "config.json" | Select-Object -First 1 | Get-Content | ConvertFrom-Json
do {
    $anyEnabled = $false
    Clear-Host
    $config.configurations | % {
        $conf = $_
        if ($conf.state -eq "enabled") {
            $anyEnabled = $true
            [double]$level = [System.Double]::Parse($conf.value)
            $prev = $conf.prev
            $stats = Get-Stats
            [double]$last = [System.Double]::Parse($stats.last)

            $obj = @{
                level         = $level
                last          = $last
                currency_from = $conf.currency_pair.Substring(0, 3)
                currency_to   = $conf.currency_pair.Substring(3, 3)
                type          = $conf.type
            }

            $toGo = [System.Math]::Abs($level - $last)
            Write-Host "---- $($conf.currency_pair) ----" -ForegroundColor Yellow
            Write-Host "type:          $($conf.type)"
            Write-Host "last:          $last $($obj.currency_to)"
            Write-Host "level:         $level $($obj.currency_to)"
            Write-Host "prev:          '$prev'"
            if ($conf.prev) {
                if ($conf.type -eq "crossing-up") {
                    if ($prev -eq "below") {
                        if ($last -ge $level) {
                            Write-Message $conf.message $obj
                            Update-State $conf
                        }
                        else {
                            Write-Host "to go:        [$toGo]" -ForegroundColor Green
                        }
                    }
                    else {
                        Write-Host "Current value is $prev desired level. Condition will not be checked" -ForegroundColor Red
                    }
                }
                if ($conf.type -eq "crossing-down") {
                    if ($prev -eq "above") {
                        if ($last -le $level) {
                            Write-Message $conf.message $obj
                            Update-State $conf
                        }
                        else {
                            Write-Host "to go:        [$toGo]" -ForegroundColor Green
                        }
                    }
                    else {
                        Write-Host "Current value is $prev desired level. Condition will not be checked" -ForegroundColor Red
                    }
                }
                if ($conf.type -eq "crossing") {
                    $falling = $prev -eq "above" -and $last -le $level
                    $rising = $prev -eq "below" -and $last -ge $level
                    if ($falling -or $rising) {
                        Write-Message $conf.message $obj
                        Update-State $conf
                    }
                    else {
                        Write-Host "to go:        [$toGo]" -ForegroundColor Green
                    }
                }
            }

            $val = $null
            if ($last -gt $level) {
                $val = "above"
            }
            if ($last -lt $level) {
                $val = "below"
            }
            if ($last -eq $level) {
                $val = "equal"
            }
            if (!$conf.prev -and $val) {
                $conf | Add-Member -NotePropertyName prev -NotePropertyValue $val
            }
            else {
                $conf.prev = $val
            }
        }
    }
    Start-Sleep -Seconds 10
} while ($anyEnabled)

