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

function Test-Expired {
    param ($conf)
    $conf.expiration -and $conf.expiration -le [datetime]::UtcNow
}

function Get-Stats {
    param ($ids)
    $list = [string]::Join(',', $ids)
    $stats = Invoke-WebRequest -Uri "https://api.coingecko.com/api/v3/simple/price?ids=$list&vs_currencies=usd" -Method Get | ConvertFrom-Json
    $stats
}

$config = Get-ChildItem $PSScriptRoot -Filter "config.json" | Select-Object -First 1 | Get-Content | ConvertFrom-Json
$ids = $config.configurations.currency_pair | Select-Object -Unique
do {
    $anyEnabled = $false
    Clear-Host
    $stats = Get-Stats $ids
    $config.configurations | ? { !(Test-Expired $_) } | % {
        $conf = $_
        if ($conf.state -eq "enabled") {
            $anyEnabled = $true
            [double]$level = [System.Double]::Parse($conf.value)
            $prev = $conf.prev
            $curka = $conf.currency_pair
            [double]$last = [System.Double]::Parse($stats."$curka".usd)

            $obj = @{
                level         = $level
                last          = $last
                currency_from = $conf.currency_pair
                currency_to   = 'USD'
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
    Start-Sleep -Seconds 30
} while ($anyEnabled)

