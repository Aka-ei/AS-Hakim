param(
    [string]$PackageRoot = "",
    [ValidateSet("Interactive", "Install", "Uninstall")]
    [string]$Mode = "Interactive",
    [string]$GameDir = "",
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

try {
    $Host.UI.RawUI.WindowTitle = "Phoenix Wright: Ace Attorney Trilogy - Türkçe Yama Kurulumu"
} catch {}

if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = Split-Path -Path $PSScriptRoot -Parent
}
$PackageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path
$PatchDataRoot = Join-Path $PackageRoot "Yama_Dosyalari\PWAAT_Data"

function Write-Header {
    Clear-Host
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "   PHOENIX WRIGHT: ACE ATTORNEY TRILOGY - TÜRKÇE YAMA KURULUMU" -ForegroundColor Yellow
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "   Kapsam: 1., 2. ve 3. Oyun (GS1, GS2, GS3), Menüler," -ForegroundColor Gray
    Write-Host "           Türkçe Font Yaması ve 62 Adet Oyun İçi Görsel" -ForegroundColor Gray
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Test-ValidGameDir([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    $exe  = Join-Path $Path "PWAAT.exe"
    $data = Join-Path $Path "PWAAT_Data"
    return (Test-Path -LiteralPath $exe -PathType Leaf) -and (Test-Path -LiteralPath $data -PathType Container)
}

function Normalize-GameDir([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    $clean = $Path.Trim().Trim('"').TrimEnd('\', '/')
    if (Test-ValidGameDir $clean) { return $clean }
    # Kullanıcı yanlışlıkla PWAAT_Data klasörünü seçtiyse üst klasörü kontrol et
    if ((Split-Path -Leaf $clean) -ieq "PWAAT_Data") {
        $parent = Split-Path -Parent $clean
        if (Test-ValidGameDir $parent) { return $parent }
    }
    return $clean
}

function Find-GameDirectory {
    $candidates = New-Object System.Collections.Generic.List[string]

    # 1. Paketin bulunduğu veya bir üst klasör
    $candidates.Add($PackageRoot)
    $parentDir = Split-Path -Parent $PackageRoot
    if ($parentDir) { $candidates.Add($parentDir) }

    # 2. Steam kütüphane klasörlerini Registry ve libraryfolders.vdf üzerinden tara
    $steamPaths = @()
    foreach ($regPath in @("HKCU:\Software\Valve\Steam", "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam", "HKLM:\SOFTWARE\Valve\Steam")) {
        try {
            $val = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).SteamPath
            if (-not $val) { $val = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).InstallPath }
            if ($val -and (Test-Path -LiteralPath $val)) {
                $steamPaths += ($val -replace '/', '\')
            }
        } catch {}
    }

    foreach ($sp in ($steamPaths | Select-Object -Unique)) {
        $candidates.Add((Join-Path $sp "steamapps\common\Phoenix Wright Ace Attorney Trilogy"))
        $vdfPath = Join-Path $sp "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $vdfPath) {
            try {
                $vdfContent = Get-Content -LiteralPath $vdfPath -Raw -Encoding UTF8
                $matches = [regex]::Matches($vdfContent, '"path"\s+"([^"]+)"')
                foreach ($m in $matches) {
                    $libPath = $m.Groups[1].Value -replace '\\\\', '\'
                    $candidates.Add((Join-Path $libPath "steamapps\common\Phoenix Wright Ace Attorney Trilogy"))
                }
            } catch {}
        }
    }

    # 3. Tüm yerel disklerde yaygın kurulum yolları
    try {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' }
        foreach ($d in $drives) {
            $r = $d.Root
            $candidates.Add((Join-Path $r "Program Files (x86)\Steam\steamapps\common\Phoenix Wright Ace Attorney Trilogy"))
            $candidates.Add((Join-Path $r "Program Files\Steam\steamapps\common\Phoenix Wright Ace Attorney Trilogy"))
            $candidates.Add((Join-Path $r "SteamLibrary\steamapps\common\Phoenix Wright Ace Attorney Trilogy"))
            $candidates.Add((Join-Path $r "Games\Phoenix Wright Ace Attorney Trilogy"))
            $candidates.Add((Join-Path $r "Oyunlar\Phoenix Wright Ace Attorney Trilogy"))
        }
    } catch {}

    foreach ($c in ($candidates | Select-Object -Unique)) {
        if (Test-ValidGameDir $c) {
            # Paketin kendi içindeki klasör olmasın
            if (-not $c.StartsWith($PackageRoot, [StringComparison]::OrdinalIgnoreCase)) {
                return $c
            }
            # Paketin kendisi oyun klasörünün içindeyse üst klasör zaten geçerlidir
            if ($c -ieq $PackageRoot -and (Test-ValidGameDir $c)) {
                return $c
            }
        }
    }
    return $null
}

function Show-FolderDialog {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $owner = New-Object System.Windows.Forms.Form
        $owner.TopMost = $true
        $owner.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $owner.Opacity = 0
        $owner.ShowInTaskbar = $false
        $owner.Show()

        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "PWAAT.exe dosyasının bulunduğu oyun klasörünü seçin:"
        $dialog.ShowNewFolderButton = $false

        $result = $dialog.ShowDialog($owner)
        $selected = $dialog.SelectedPath
        $owner.Close()
        $owner.Dispose()
        $dialog.Dispose()

        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            return $selected
        }
    } catch {
        return $null
    }
    return $null
}

function Prompt-GameDirectory {
    $detected = Find-GameDirectory
    if ($detected) {
        Write-Host "Oyun klasörü otomatik olarak bulundu:" -ForegroundColor Green
        Write-Host "  $detected" -ForegroundColor White
        Write-Host ""
        $ans = Read-Host "Bu klasör kullanılsın mı? [E/H] (Varsayılan: E)"
        if ([string]::IsNullOrWhiteSpace($ans) -or $ans.Trim().ToUpperInvariant() -eq "E") {
            return $detected
        }
    } else {
        Write-Host "Oyun klasörü otomatik bulunamadı." -ForegroundColor Yellow
    }

    while ($true) {
        Write-Host ""
        Write-Host "Oyun klasörünü (PWAAT.exe dosyasının bulunduğu yer) nasıl seçmek istersiniz?" -ForegroundColor Cyan
        Write-Host "  [1] Klasör Seçme Penceresi Aç (Önerilen)"
        Write-Host "  [2] Klasör Yolunu Elle Yaz / Yapıştır"
        Write-Host "  [0] İptal / Ana Menü"
        $sel = Read-Host "Seçiminiz"

        if ($sel -eq "0") { return $null }

        $chosen = $null
        if ($sel -eq "1" -or [string]::IsNullOrWhiteSpace($sel)) {
            Write-Host "Klasör seçme penceresi açılıyor..." -ForegroundColor Gray
            $chosen = Show-FolderDialog
            if (-not $chosen) {
                Write-Host "Klasör seçilmedi." -ForegroundColor Yellow
                continue
            }
        } elseif ($sel -eq "2") {
            $chosen = Read-Host "Oyun klasörünün tam yolunu yapıştırın"
        } else {
            Write-Host "Geçersiz seçim." -ForegroundColor Red
            continue
        }

        $normalized = Normalize-GameDir $chosen
        if (Test-ValidGameDir $normalized) {
            return $normalized
        } else {
            Write-Host ""
            Write-Host "[HATA] Seçilen klasörde 'PWAAT.exe' veya 'PWAAT_Data' bulunamadı!" -ForegroundColor Red
            Write-Host "Seçilen yol: $chosen" -ForegroundColor DarkGray
            Write-Host "Lütfen doğrudan oyunun kurulu olduğu ana klasörü seçin." -ForegroundColor Yellow
        }
    }
}

function Install-Patch([string]$TargetGameDir) {
    if (-not (Test-Path -LiteralPath $PatchDataRoot -PathType Container)) {
        throw "Yama dosyaları bulunamadı: $PatchDataRoot"
    }

    $running = Get-Process -Name "PWAAT" -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host "[UYARI] Oyun (PWAAT.exe) şu anda çalışıyor görünüyor!" -ForegroundColor Red
        Write-Host "Lütfen önce oyunu kapatın ve ardından tekrar deneyin." -ForegroundColor Yellow
        return $false
    }

    $patchFiles = Get-ChildItem -LiteralPath $PatchDataRoot -Recurse -File
    $total = $patchFiles.Count
    if ($total -eq 0) {
        throw "Yama klasöründe kopyalanacak dosya bulunamadı."
    }

    $targetDataRoot = Join-Path $TargetGameDir "PWAAT_Data"
    $backupDataRoot = Join-Path $TargetGameDir "TR_Yama_Yedek\PWAAT_Data"

    Write-Host ""
    Write-Host "Kurulum hedefi : $TargetGameDir" -ForegroundColor Cyan
    Write-Host "Yama dosya adedi: $total dosya" -ForegroundColor Cyan
    Write-Host ""

    # 1. Yedekleme (Yalnızca daha önce yedek alınmadıysa orijinal dosyaları yedekle)
    if (Test-Path -LiteralPath $backupDataRoot -PathType Container) {
        Write-Host "[1/3] Mevcut orijinal yedek bulundu, üzerine yazılmadan korundu:" -ForegroundColor Green
        Write-Host "      $backupDataRoot" -ForegroundColor Gray
    } else {
        Write-Host "[1/3] Orijinal oyun dosyaları yedekleniyor..." -ForegroundColor Yellow
        $backedUp = 0
        foreach ($pf in $patchFiles) {
            $rel = $pf.FullName.Substring($PatchDataRoot.Length)
            $origFile = Join-Path $targetDataRoot $rel
            if (Test-Path -LiteralPath $origFile -PathType Leaf) {
                $bakFile = Join-Path $backupDataRoot $rel
                $bakDir = Split-Path -Parent $bakFile
                if (-not (Test-Path -LiteralPath $bakDir)) {
                    New-Item -ItemType Directory -Path $bakDir -Force | Out-Null
                }
                Copy-Item -LiteralPath $origFile -Destination $bakFile -Force
                $backedUp++
            }
        }
        Write-Host "      $backedUp orijinal dosya yedeklendi -> TR_Yama_Yedek\" -ForegroundColor Green
    }

    # 2. Yama dosyalarını kopyala
    Write-Host "[2/3] Türkçe yama dosyaları kopyalanıyor..." -ForegroundColor Yellow
    $copied = 0
    foreach ($pf in $patchFiles) {
        $rel = $pf.FullName.Substring($PatchDataRoot.Length)
        $dstFile = Join-Path $targetDataRoot $rel
        $dstDir = Split-Path -Parent $dstFile
        if (-not (Test-Path -LiteralPath $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $pf.FullName -Destination $dstFile -Force
        $copied++
        if (($copied % 25 -eq 0) -or ($copied -eq $total)) {
            $pct = [math]::Floor(($copied / $total) * 100)
            Write-Host "`r      İlerleme: $copied / $total (%$pct)   " -NoNewline -ForegroundColor Gray
        }
    }
    Write-Host ""

    # 3. Doğrulama
    Write-Host "[3/3] Kopyalanan dosyalar doğrulanıyor..." -ForegroundColor Yellow
    $verified = 0
    foreach ($pf in $patchFiles) {
        $rel = $pf.FullName.Substring($PatchDataRoot.Length)
        $dstFile = Join-Path $targetDataRoot $rel
        if ((Test-Path -LiteralPath $dstFile -PathType Leaf) -and ((Get-Item -LiteralPath $dstFile).Length -eq $pf.Length)) {
            $verified++
        } else {
            throw "Doğrulama hatası: $rel"
        }
    }

    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Green
    Write-Host "   KURULUM BAŞARIYLA TAMAMLANDI! ($verified / $total dosya)" -ForegroundColor Green
    Write-Host "=================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "ÖNEMLİ HATIRLATMALAR:" -ForegroundColor Yellow
    Write-Host "  * Oyun içi dil ayarının 'English' (İngilizce) olduğundan emin olun." -ForegroundColor White
    Write-Host "    (Türkçe yama İngilizce dil dosyalarının üzerine kurulmuştur.)" -ForegroundColor Gray
    Write-Host "  * İstediğiniz zaman Kurulum.bat -> [2] ile orijinale dönebilirsiniz." -ForegroundColor White

    if ($TargetGameDir -match '[^\x20-\x7E]') {
        Write-Host ""
        Write-Host "[NOT] Oyun klasör yolunda Türkçe/özel karakter tespit edildi:" -ForegroundColor Yellow
        Write-Host "      $TargetGameDir" -ForegroundColor DarkYellow
        Write-Host "      Oyun açılışta hata verirse oyun klasörünü Türkçe karakter" -ForegroundColor Gray
        Write-Host "      içermeyen bir yola (ör. C:\Games\PWAAT) taşımanız önerilir." -ForegroundColor Gray
    }
    return $true
}

function Uninstall-Patch([string]$TargetGameDir) {
    $running = Get-Process -Name "PWAAT" -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host "[UYARI] Oyun (PWAAT.exe) şu anda çalışıyor görünüyor! Önce oyunu kapatın." -ForegroundColor Red
        return $false
    }

    $targetDataRoot = Join-Path $TargetGameDir "PWAAT_Data"
    $backupRoot = Join-Path $TargetGameDir "TR_Yama_Yedek"
    $backupDataRoot = Join-Path $backupRoot "PWAAT_Data"

    if (-not (Test-Path -LiteralPath $backupDataRoot -PathType Container)) {
        Write-Host ""
        Write-Host "[HATA] Bu oyun klasöründe otomatik yedek bulunamadı:" -ForegroundColor Red
        Write-Host "       $backupDataRoot" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "Steam kullanıyorsanız Steam -> Özellikler -> Yüklü Dosyalar ->" -ForegroundColor Yellow
        Write-Host "'Oyun dosyalarının bütünlüğünü doğrula' seçeneğiyle orijinale dönebilirsiniz." -ForegroundColor Yellow
        return $false
    }

    $bakFiles = Get-ChildItem -LiteralPath $backupDataRoot -Recurse -File
    $total = $bakFiles.Count
    Write-Host ""
    Write-Host "Orijinal dosyalar geri yükleniyor ($total dosya)..." -ForegroundColor Yellow

    $restored = 0
    foreach ($bf in $bakFiles) {
        $rel = $bf.FullName.Substring($backupDataRoot.Length)
        $dstFile = Join-Path $targetDataRoot $rel
        $dstDir = Split-Path -Parent $dstFile
        if (-not (Test-Path -LiteralPath $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $bf.FullName -Destination $dstFile -Force
        $restored++
    }

    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Green
    Write-Host "   ORİJİNAL DOSYALAR GERİ YÜKLENDİ! ($restored / $total dosya)" -ForegroundColor Green
    Write-Host "=================================================================" -ForegroundColor Green

    if ($Mode -eq "Interactive") {
        Write-Host ""
        $del = Read-Host "Yedek klasörü (TR_Yama_Yedek) silinsin mi? [E/H] (Varsayılan: H)"
        if ($del.Trim().ToUpperInvariant() -eq "E") {
            Remove-Item -LiteralPath $backupRoot -Recurse -Force
            Write-Host "TR_Yama_Yedek klasörü temizlendi." -ForegroundColor Gray
        }
    }
    return $true
}

# --- ANA AKIŞ ---
try {
    if ($Mode -eq "Install") {
        $norm = Normalize-GameDir $GameDir
        if (-not (Test-ValidGameDir $norm)) { throw "Geçersiz oyun klasörü: $GameDir" }
        $ok = Install-Patch $norm
        if (-not $ok) { exit 1 }
        exit 0
    }
    elseif ($Mode -eq "Uninstall") {
        $norm = Normalize-GameDir $GameDir
        if (-not (Test-ValidGameDir $norm)) { throw "Geçersiz oyun klasörü: $GameDir" }
        $ok = Uninstall-Patch $norm
        if (-not $ok) { exit 1 }
        exit 0
    }

    while ($true) {
        Write-Header
        Write-Host "Lütfen yapmak istediğiniz işlemi seçin:" -ForegroundColor White
        Write-Host ""
        Write-Host "  [1] Türkçe Yamayı Kur (Otomatik Yedekli)" -ForegroundColor Green
        Write-Host "  [2] Yamayı Kaldır / Orijinal Dosyaları Geri Yükle" -ForegroundColor Yellow
        Write-Host "  [3] Çıkış" -ForegroundColor Gray
        Write-Host ""
        $choice = Read-Host "Seçiminiz (1-3)"

        switch ($choice.Trim()) {
            "1" {
                Write-Header
                $dir = Prompt-GameDirectory
                if ($dir) {
                    Install-Patch $dir | Out-Null
                    Write-Host ""
                    if (-not $NoPause) { Read-Host "Ana menüye dönmek için Enter'a basın" }
                }
            }
            "2" {
                Write-Header
                $dir = Prompt-GameDirectory
                if ($dir) {
                    Uninstall-Patch $dir | Out-Null
                    Write-Host ""
                    if (-not $NoPause) { Read-Host "Ana menüye dönmek için Enter'a basın" }
                }
            }
            "3" {
                break
            }
            default {
                Write-Host "Lütfen 1, 2 veya 3 girin." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
        if ($choice.Trim() -eq "3") { break }
    }
}
catch {
    Write-Host ""
    Write-Host "[HATA] Bir sorun oluştu:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if (-not $NoPause) {
        Write-Host ""
        Read-Host "Kapatmak için Enter'a basın"
    }
    exit 1
}
