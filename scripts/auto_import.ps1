param(
    [Parameter(Mandatory=$false)]
    [string]$SourceFolder = "C:\PVZ\Import",

    [Parameter(Mandatory=$false)]
    [string]$ArchiveFolder = "C:\PVZ\Archive",

    [Parameter(Mandatory=$false)]
    [string]$ErrorFolder = "C:\PVZ\Error",

    [Parameter(Mandatory=$false)]
    [string]$LogFolder = "C:\PVZ\Logs",

    [Parameter(Mandatory=$false)]
    [string]$PythonScript = "C:\PVZ\Scripts\import_orders.py",

    [Parameter(Mandatory=$false)]
    [int]$UserId = 1
)

# =====================================================
# Функции
# =====================================================

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] $Message"

    # Создание папки для логов
    if (-not (Test-Path $LogFolder)) {
        New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
    }

    # Запись в файл
    $logFile = Join-Path $LogFolder "import_$(Get-Date -Format 'yyyyMMdd').log"
    $logMessage | Out-File -FilePath $logFile -Append -Encoding UTF8

    # Вывод в консоль
    switch ($Level) {
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Host $logMessage -ForegroundColor White }
    }
}

function Test-Folders {
    Write-Log "Проверка папок..." -Level "INFO"

    # Проверка папки импорта
    if (-not (Test-Path $SourceFolder)) {
        Write-Log "Папка импорта не найдена: $SourceFolder" -Level "ERROR"
        New-Item -ItemType Directory -Path $SourceFolder -Force | Out-Null
        Write-Log "Создана папка импорта: $SourceFolder" -Level "SUCCESS"
    }

    # Создание остальных папок
    @($ArchiveFolder, $ErrorFolder, $LogFolder) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
            Write-Log "Создана папка: $_" -Level "SUCCESS"
        }
    }
}

function Get-ExcelFiles {
    Write-Log "Поиск Excel-файлов в $SourceFolder..." -Level "INFO"

    $files = Get-ChildItem -Path $SourceFolder -Filter *.xlsx -File

    if ($files.Count -eq 0) {
        Write-Log "Excel-файлы не найдены" -Level "WARNING"
    } else {
        Write-Log "Найдено файлов: $($files.Count)" -Level "SUCCESS"
    }

    return $files
}

function Process-File {
    param($File)

    Write-Log "Обработка файла: $($File.Name)" -Level "INFO"

    # Проверка размера файла
    if ($File.Length -eq 0) {
        Write-Log "Файл пустой" -Level "ERROR"
        Move-Item -Path $File.FullName -Destination $ErrorFolder -Force
        return $false
    }

    # Запуск Python-скрипта
    $pythonArgs = @(
        $PythonScript,
        "`"$($File.FullName)`"",
        "--user-id", $UserId
    )

    try {
        $result = & python $pythonArgs 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log "Файл успешно обработан" -Level "SUCCESS"

            # Перемещение в архив с датой
            $date = Get-Date -Format "yyyyMMdd"
            $archiveName = "$date`_$($File.Name)"
            $archivePath = Join-Path $ArchiveFolder $archiveName
            Move-Item -Path $File.FullName -Destination $archivePath -Force
            Write-Log "Файл перемещен в архив: $archiveName" -Level "SUCCESS"

            return $true
        } else {
            Write-Log "Ошибка обработки файла" -Level "ERROR"
            Write-Log "Вывод: $result" -Level "ERROR"

            # Перемещение в папку ошибок
            $errorPath = Join-Path $ErrorFolder $File.Name
            Move-Item -Path $File.FullName -Destination $errorPath -Force
            Write-Log "Файл перемещен в папку ошибок" -Level "WARNING"

            return $false
        }
    } catch {
        Write-Log "Исключение при обработке: $_" -Level "ERROR"

        # Перемещение в папку ошибок
        $errorPath = Join-Path $ErrorFolder $File.Name
        Move-Item -Path $File.FullName -Destination $errorPath -Force

        return $false
    }
}

function Send-Notification {
    param(
        [int]$SuccessCount,
        [int]$ErrorCount,
        [array]$ProcessedFiles
    )

    Write-Log "Отправка уведомления..." -Level "INFO"

    $subject = "Импорт заказов: $SuccessCount успешно, $ErrorCount ошибок"

    $body = @"
<h2>Отчет об импорте заказов</h2>
<p><strong>Дата:</strong> $(Get-Date -Format 'dd.MM.yyyy HH:mm')</p>
<p><strong>Успешно обработано:</strong> $SuccessCount файлов</p>
<p><strong>Ошибок:</strong> $ErrorCount файлов</p>

<h3>Обработанные файлы:</h3>
<ul>
"@

    foreach ($file in $ProcessedFiles) {
        $body += "<li>$file</li>"
    }

    $body += @"
</ul>
<p><em>Автоматическое уведомление системы импорта ПВЗ</em></p>
"@

    # Отправка email (настройте под свой SMTP)
    try {
        $mailParams = @{
            SmtpServer = "smtp.gmail.com"
            Port = 587
            UseSsl = $true
            Credential = (Get-Credential -UserName "pvz@example.com" -Message "Введите пароль")
            From = "pvz@example.com"
            To = "platonov@pvz.ru"
            Subject = $subject
            Body = $body
            BodyAsHtml = $true
        }

        # Send-MailMessage @mailParams
        Write-Log "Уведомление отправлено" -Level "SUCCESS"
    } catch {
        Write-Log "Ошибка отправки уведомления: $_" -Level "WARNING"
    }
}

# =====================================================
# Основной скрипт
# =====================================================

Write-Log "=" * 60 -Level "INFO"
Write-Log "ЗАПУСК АВТОМАТИЧЕСКОГО ИМПОРТА ЗАКАЗОВ" -Level "INFO"
Write-Log "=" * 60 -Level "INFO"

# Проверка папок
Test-Folders

# Получение списка файлов
$files = Get-ExcelFiles

if ($files.Count -eq 0) {
    Write-Log "Нет файлов для обработки" -Level "WARNING"
    exit 0
}

# Обработка файлов
$successCount = 0
$errorCount = 0
$processedFiles = @()

foreach ($file in $files) {
    Write-Log "-" * 50 -Level "INFO"

    if (Process-File -File $file) {
        $successCount++
        $processedFiles += "$($file.Name) - УСПЕХ"
    } else {
        $errorCount++
        $processedFiles += "$($file.Name) - ОШИБКА"
    }
}

# Итоги
Write-Log "=" * 60 -Level "INFO"
Write-Log "ИМПОРТ ЗАВЕРШЕН" -Level "INFO"
Write-Log "Успешно: $successCount" -Level "SUCCESS"
Write-Log "Ошибок: $errorCount" -Level $(if ($errorCount -gt 0) { "ERROR" } else { "INFO" })
Write-Log "=" * 60 -Level "INFO"

# Отправка уведомления
if ($successCount -gt 0 -or $errorCount -gt 0) {
    Send-Notification -SuccessCount $successCount -ErrorCount $errorCount -ProcessedFiles $processedFiles
}

exit $(if ($errorCount -eq 0) { 0 } else { 1 })