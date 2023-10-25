$FORMAT_ISO_8601 = "yyyy-MM-ddTHHmmss"
$REGEX_ISO_8601 = "\d{4}-\d{2}-\d{2}T\d{2}\d{2}\d{2}"
$DateTimeStart = Get-Date -format $FORMAT_ISO_8601

$Machine = "MyComputerName"
#$SourceInstance = "MSSQLSERVER"
$SourceDatabase = "MyDatabaseName"
$SourceSchema = "MySchemaName"
$SourceSchemaLog = "MySchemaName_log"

$ExportLogFolder = "C:\Users\Public\PowerShell\MSSQL_Export"
#$ExportLogFile = "$($Machine)_$($SourceInstance)_$($SourceDatabase).log"
$ExportLogFile = "$($Machine)_$($SourceDatabase).log"

try {
    Import-Module SQLPS -ErrorAction Stop
}
catch {
    Write-Host $Error[0].Exception.GetType().FullName
    Write-Host $PSItem.ToString()
    Exit
}

if (!(Test-Path -Path "$($ExportLogFolder)\$($ExportLogFile)" -PathType Leaf)) {
    if (!(Test-Path -Path "$($ExportLogFolder)" -PathType Container)) {
        try {
            New-Item -Path "$($ExportLogFolder)" -ItemType "directory" -ErrorAction Stop
        }
        catch {
            Write-Host($Error[0].Exception.GetType().FullName)
            Write-Host($PSItem.ToString())
            Exit
        }
    }
}
Function LogWrite {
    Param ([string]$LogString)
    Add-Content "$($ExportLogFolder)\$($ExportLogFile)" -value $LogString
    Write-Host $LogString
}
LogWrite "________"

$ExportFolder = "C:\Users\Public\PowerShell\MSSQL_Export"
#$ExportFile = "$($SourceInstance)_$($SourceDatabase)_$($DateTimeStart).bak"
$ExportFile = "$($SourceDatabase)_$($DateTimeStart).bak"
if (!(Test-Path -Path "$($ExportFolder)\$($DateTimeStart)\$($ExportFile)" -PathType Leaf)) {
    if (!(Test-Path -Path "$($ExportFolder)\$($DateTimeStart)" -PathType Container)) {
        try {
            New-Item -Path "$($ExportFolder)\$($DateTimeStart)" -ItemType "directory" -ErrorAction Stop
        }
        catch {
            Write-Host($Error[0].Exception.GetType().FullName)
            Write-Host($PSItem.ToString())
            Exit
        }
    }
}

$NetworkDrive = "V:"

$LoopCount = 1
while (1) {
    try {
        # I am not using Test-Path here because Test-Path is frustratingly unreliable with network SMB.
        Set-Content -Path "$($NetworkDrive)\$($DateTimeStart).txt" -Value $DateTimeStart -ErrorAction Stop
        Remove-Item -Path "$($NetworkDrive)\$($DateTimeStart).txt" -Recurse -Force -Confirm:$false -ErrorAction Stop
        LogWrite "Successfully connected drive $($NetworkDrive)\"
        Break
    }
    catch {
        if ($LoopCount -gt 1) {
            LogWrite $($Error[0].Exception.GetType().FullName)
            LogWrite $($PSItem.ToString())
        }
    }
    if ($LoopCount -gt 1) {
        LogWrite "Failed to connect drive $($NetworkDrive)\"
        Exit
    }
    LogWrite "Connecting drive $($NetworkDrive)\"
    try {
        # I am not using New-PSDrive here because New-PSDrive is bafflingly unreliable with network SMB.
        (New-Object -ComObject WScript.Network).MapNetworkDrive($NetworkDrive, "\\169.254.127.127\MSSQL_Exports", $false, "MyServer\MyUsername", "MyPassword")
        # TODO - Implement PSCredential for providing the network drive credentials.
    }
    catch {
        LogWrite $($Error[0].Exception.GetType().FullName)
        LogWrite $($PSItem.ToString())
        Exit
    }
    $LoopCount ++
}

$Upload = $false

try {
    $SQL_Export = @"
        USE [$($SourceDatabase)]
        ALTER DATABASE [$($SourceDatabase)] SET RECOVERY SIMPLE
        DBCC SHRINKFILE ('$($SourceSchemaLog)', 1)
        BACKUP DATABASE [$($SourceDatabase)]
        TO DISK = '$($ExportFolder)\$($DateTimeStart)\$($ExportFile)'
"@
#    Invoke-Sqlcmd $SQL_Export -ServerInstance "$($Machine)\$($SourceInstance)" -ErrorAction Stop
#    LogWrite "OK: Exported ""$($SourceDatabase)"" database in ""$($SourceInstance)"" instance to ""$($ExportFolder)\$($DateTimeStart)\$($ExportFile)"""
    Invoke-Sqlcmd $SQL_Export -ServerInstance "$($Machine)" -ErrorAction Stop
    LogWrite "OK: Exported ""$($SourceDatabase)"" database to ""$($ExportFolder)\$($DateTimeStart)\$($ExportFile)"""
    $Upload = $true
}
catch {
    LogWrite $($Error[0].Exception.GetType().FullName)
    LogWrite $($PSItem.ToString())
    Exit
}

if ($Upload) {
    try {
        $DateTimeUpload = Get-Date -format $FORMAT_ISO_8601
        LogWrite "Upload ""$($ExportFolder)\$($DateTimeStart)\$($ExportFile)"" to drive $($NetworkDrive)\"
        Copy-Item -Path "$($ExportFolder)\$($DateTimeStart)\$($ExportFile)" -Destination $NetworkDrive  -ErrorAction Stop
        #LogWrite (Get-Content -Path "$($ExportPath)\$($DateTimeExport)\stdout.log")
        $DateTimeStop = Get-Date -format $FORMAT_ISO_8601
        LogWrite "Upload ended $($DateTimeStop)"
    }
    catch {
        LogWrite $($Error[0].Exception.GetType().FullName)
        LogWrite $($PSItem.ToString())
    }    
}

if ($Upload) {
    try {
        LogWrite "Cleanup ""$($ExportFolder)\$($DateTimeStart)""" 
        Remove-Item "$($ExportFolder)\$($DateTimeStart)" -Recurse -Force -Confirm:$false -ErrorAction Stop
    }
    catch {
        LogWrite $($Error[0].Exception.GetType().FullName)
        LogWrite $($PSItem.ToString())
    }    
}

$DateTimeStop = Get-Date -format $FORMAT_ISO_8601
LogWrite "Done. $($DateTimeStop)"
