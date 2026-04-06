<#
.SYNOPSIS
    Skenario Uji Coba Code Interpreter - Bahasa Indonesia
    5 Use Case dengan dataset 100+ record
.DESCRIPTION
    Setiap use case mengunggah dataset, mengirim prompt dalam Bahasa Indonesia,
    dan memverifikasi output berupa tabel CSV dan grafik PNG.
#>
param(
    [string]$BaseUrl = $(if ($env:INGRESS_IP) { "http://$env:INGRESS_IP" } else { "http://localhost:8000" })
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

$pass = 0
$fail = 0

function OK { param([string]$m); $script:pass++; Write-Host "  [LULUS] $m" -ForegroundColor Green }
function NG { param([string]$m); $script:fail++; Write-Host "  [GAGAL] $m" -ForegroundColor Red }

function Send-Chat {
    param([string]$Prompt, [string]$BlobPath, [string]$SessionId)
    $body = @{ prompt = $Prompt; dataset_blob = $BlobPath; session_id = $SessionId } | ConvertTo-Json -Depth 3
    $tmpFile = Join-Path $ProjectRoot "scripts\_tmp_chat.json"
    [System.IO.File]::WriteAllText($tmpFile, $body, [System.Text.UTF8Encoding]::new($false))
    $raw = curl.exe -s -X POST "$BaseUrl/api/chat" -H "Content-Type: application/json" --data-binary "@$tmpFile" --max-time 660
    Remove-Item $tmpFile -ErrorAction SilentlyContinue
    return ($raw | ConvertFrom-Json)
}

function Upload-Dataset {
    param([string]$FileName)
    $raw = curl.exe -s -X POST "$BaseUrl/api/upload" -F "file=@sample-data/$FileName"
    return ($raw | ConvertFrom-Json)
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Skenario Uji Coba - Bahasa Indonesia"       -ForegroundColor Cyan
Write-Host "  5 Use Case x Data 100+ Record"              -ForegroundColor Cyan
Write-Host "  Endpoint: $BaseUrl"                          -ForegroundColor Gray
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Setiap use case memerlukan 1-5 menit. Total: 10-25 menit." -ForegroundColor Yellow
Write-Host ""

# ============================================================================
# USE CASE 1: Deteksi Anomali Transaksi (150 record)
# Ekspektasi: Tabel transaksi mencurigakan + Box plot + Bar chart
# ============================================================================
Write-Host "==== USE CASE 1: Deteksi Anomali Transaksi ====" -ForegroundColor Cyan
Write-Host "  Dataset: transaksi_nasabah.csv (150 record)"
Write-Host "  Ekspektasi: Tabel anomali + Box plot + Bar chart"
Write-Host ""

$p1 = "Analisis data transaksi nasabah ini dan identifikasi transaksi yang mencurigakan atau anomali. " +
      "Hitung rata-rata dan standar deviasi jumlah transaksi. " +
      "Tandai transaksi yang jumlahnya lebih dari 3 standar deviasi di atas rata-rata. " +
      "Buat tabel berisi transaksi mencurigakan (transaction_id, tanggal, jumlah, merchant, channel, kota). " +
      "Buat box plot distribusi jumlah transaksi untuk menunjukkan outlier. " +
      "Buat bar chart jumlah transaksi per merchant untuk yang mencurigakan. " +
      "Analisis pola terkait channel atau merchant Unknown. " +
      "Simpan tabel sebagai CSV dan grafik sebagai PNG."

Write-Host "  [1/3] Mengunggah..."
$u1 = Upload-Dataset "transaksi_nasabah.csv"
if ($u1.session_id) { OK "Upload: $($u1.filename)" } else { NG "Upload gagal" }

Write-Host "  [2/3] Mengirim prompt (1-5 menit)..."
$c1 = Send-Chat -Prompt $p1 -BlobPath $u1.blob_path -SessionId $u1.session_id

Write-Host "  [3/3] Verifikasi..."
if ($c1.status -eq "completed") { OK "Status: selesai" } else { NG "Status: $($c1.status)" }
if ($c1.code) { OK "Kode: $($c1.code.Length) karakter" } else { NG "Tidak ada kode" }
if ($c1.explanation -match "anomali|mencurigakan|outlier") { OK "Analisis anomali ditemukan" } else { NG "Analisis anomali tidak ada" }
$img1 = @($c1.output_files | Where-Object { $_.type -eq "image" })
$dat1 = @($c1.output_files | Where-Object { $_.type -eq "data" })
if ($img1.Count -gt 0) { OK "Grafik: $($img1.Count) PNG" } else { NG "Tidak ada grafik" }
if ($dat1.Count -gt 0) { OK "Tabel: $($dat1.Count) CSV" } else { NG "Tidak ada CSV" }

Write-Host ""

# ============================================================================
# USE CASE 2: Analisis Risiko Portofolio Kredit (120 record)
# Ekspektasi: Klasifikasi kolektibilitas + Pie chart + Heatmap
# ============================================================================
Write-Host "==== USE CASE 2: Risiko Portofolio Kredit ====" -ForegroundColor Cyan
Write-Host "  Dataset: portofolio_kredit.csv (120 record)"
Write-Host "  Ekspektasi: Klasifikasi kolektibilitas + Pie chart + Heatmap"
Write-Host ""

$p2 = "Lakukan analisis risiko portofolio kredit. " +
      "Klasifikasikan setiap pinjaman berdasarkan kolektibilitas DPD: " +
      "Kol 1 Lancar (DPD=0), Kol 2 Dalam Perhatian Khusus (DPD 1-90), " +
      "Kol 3 Kurang Lancar (DPD 91-120), Kol 4 Diragukan (DPD 121-180), Kol 5 Macet (DPD lebih dari 180). " +
      "Hitung total outstanding dan jumlah debitur per kolektibilitas. " +
      "Buat pie chart proporsi kolektibilitas berdasarkan jumlah pinjaman. " +
      "Buat heatmap jumlah kredit bermasalah (NPL = Kol 3+4+5) per sektor dan wilayah. " +
      "Identifikasi 5 debitur dengan risiko tertinggi. Hitung rasio NPL. " +
      "Simpan klasifikasi sebagai CSV dan grafik sebagai PNG."

Write-Host "  [1/3] Mengunggah..."
$u2 = Upload-Dataset "portofolio_kredit.csv"
if ($u2.session_id) { OK "Upload berhasil" } else { NG "Upload gagal" }

Write-Host "  [2/3] Mengirim prompt..."
$c2 = Send-Chat -Prompt $p2 -BlobPath $u2.blob_path -SessionId $u2.session_id

Write-Host "  [3/3] Verifikasi..."
if ($c2.status -eq "completed") { OK "Status: selesai" } else { NG "Status: $($c2.status)" }
if ($c2.explanation -match "kolektibilitas|NPL|macet|lancar|risiko") { OK "Klasifikasi risiko ada" } else { NG "Tidak ada klasifikasi" }
$img2 = @($c2.output_files | Where-Object { $_.type -eq "image" })
if ($img2.Count -gt 0) { OK "Grafik: $($img2.Count) PNG" } else { NG "Tidak ada grafik" }

Write-Host ""

# ============================================================================
# USE CASE 3: Dashboard Kinerja Cabang (100 record)
# Ekspektasi: Ranking + Line chart tren + Scatter plot
# ============================================================================
Write-Host "==== USE CASE 3: Dashboard Kinerja Cabang ====" -ForegroundColor Cyan
Write-Host "  Dataset: kinerja_cabang.csv (100 record, 20 cabang x 5 bulan)"
Write-Host "  Ekspektasi: Ranking cabang + Line chart + Scatter plot"
Write-Host ""

$p3 = "Analisis kinerja seluruh cabang bank. " +
      "Hitung skor komposit per cabang: pendapatan (40%), rekening baru (25%), NPS (20%), inversi keluhan (15%). " +
      "Ranking semua 20 cabang dari terbaik ke terburuk. " +
      "Buat line chart tren pendapatan bulanan untuk 5 cabang terbaik (Jan-Mei 2025). " +
      "Buat scatter plot: sumbu X pendapatan rata-rata, sumbu Y keluhan rata-rata, ukuran titik = NPS score. " +
      "Identifikasi cabang dengan masalah kualitas layanan. " +
      "Berikan rekomendasi untuk 3 cabang terburuk. " +
      "Simpan ranking sebagai CSV dan grafik sebagai PNG."

Write-Host "  [1/3] Mengunggah..."
$u3 = Upload-Dataset "kinerja_cabang.csv"
if ($u3.session_id) { OK "Upload berhasil" } else { NG "Upload gagal" }

Write-Host "  [2/3] Mengirim prompt..."
$c3 = Send-Chat -Prompt $p3 -BlobPath $u3.blob_path -SessionId $u3.session_id

Write-Host "  [3/3] Verifikasi..."
if ($c3.status -eq "completed") { OK "Status: selesai" } else { NG "Status: $($c3.status)" }
if ($c3.explanation -match "ranking|cabang|kinerja|terbaik|terburuk") { OK "Analisis kinerja ada" } else { NG "Tidak ada analisis" }
$img3 = @($c3.output_files | Where-Object { $_.type -eq "image" })
if ($img3.Count -gt 0) { OK "Grafik: $($img3.Count) PNG" } else { NG "Tidak ada grafik" }

Write-Host ""

# ============================================================================
# USE CASE 4: Segmentasi Produk Simpanan (130 record)
# Ekspektasi: Ringkasan produk + Stacked bar + Histogram
# ============================================================================
Write-Host "==== USE CASE 4: Segmentasi Produk Simpanan ====" -ForegroundColor Cyan
Write-Host "  Dataset: tabungan_deposito.csv (130 record)"
Write-Host "  Ekspektasi: Ringkasan produk + Stacked bar + Histogram"
Write-Host ""

$p4 = "Lakukan analisis segmentasi nasabah berdasarkan produk simpanan. " +
      "Hitung ringkasan per produk: jumlah nasabah, total saldo, rata-rata saldo. " +
      "Analisis distribusi nasabah per kelompok usia dan produk. " +
      "Buat stacked bar chart total saldo per produk dipecah berdasarkan kelompok usia. " +
      "Buat histogram distribusi saldo seluruh nasabah dengan garis median dan mean. " +
      "Identifikasi produk dengan rata-rata saldo tertinggi dan kelompok usia potensial untuk cross-selling. " +
      "Hitung jumlah rekening dormant dan tutup per produk. " +
      "Berikan rekomendasi strategi meningkatkan Dana Pihak Ketiga (DPK). " +
      "Simpan ringkasan sebagai CSV dan grafik sebagai PNG."

Write-Host "  [1/3] Mengunggah..."
$u4 = Upload-Dataset "tabungan_deposito.csv"
if ($u4.session_id) { OK "Upload berhasil" } else { NG "Upload gagal" }

Write-Host "  [2/3] Mengirim prompt..."
$c4 = Send-Chat -Prompt $p4 -BlobPath $u4.blob_path -SessionId $u4.session_id

Write-Host "  [3/3] Verifikasi..."
if ($c4.status -eq "completed") { OK "Status: selesai" } else { NG "Status: $($c4.status)" }
if ($c4.explanation -match "produk|saldo|tabungan|deposito|segmen|usia") { OK "Analisis segmentasi ada" } else { NG "Tidak ada analisis" }
$img4 = @($c4.output_files | Where-Object { $_.type -eq "image" })
if ($img4.Count -gt 0) { OK "Grafik: $($img4.Count) PNG" } else { NG "Tidak ada grafik" }

Write-Host ""

# ============================================================================
# USE CASE 5: Analisis Tren Fraud (110 record)
# Ekspektasi: Tren bulanan + Heatmap jenis x channel + Bar chart kerugian
# ============================================================================
Write-Host "==== USE CASE 5: Analisis Tren Fraud ====" -ForegroundColor Cyan
Write-Host "  Dataset: laporan_fraud.csv (110 record)"
Write-Host "  Ekspektasi: Line chart tren + Heatmap + Bar chart kerugian"
Write-Host ""

$p5 = "Lakukan analisis komprehensif terhadap data laporan fraud bank. " +
      "Hitung ringkasan per jenis fraud: jumlah kasus, total kerugian, rata-rata kerugian, rata-rata waktu deteksi jam. " +
      "Buat line chart tren jumlah kasus fraud per bulan dari Jun 2024 sampai Mar 2025. " +
      "Buat heatmap frekuensi fraud berdasarkan jenis_fraud (baris) vs channel (kolom). " +
      "Buat bar chart horizontal total kerugian per kota diurutkan dari tertinggi. " +
      "Analisis jenis fraud dengan kerugian rata-rata tertinggi, channel paling rentan, " +
      "rata-rata waktu deteksi, dan tingkat penyelesaian per jenis fraud. " +
      "Berikan 5 rekomendasi pencegahan fraud. " +
      "Simpan ringkasan sebagai CSV dan semua grafik sebagai PNG."

Write-Host "  [1/3] Mengunggah..."
$u5 = Upload-Dataset "laporan_fraud.csv"
if ($u5.session_id) { OK "Upload berhasil" } else { NG "Upload gagal" }

Write-Host "  [2/3] Mengirim prompt..."
$c5 = Send-Chat -Prompt $p5 -BlobPath $u5.blob_path -SessionId $u5.session_id

Write-Host "  [3/3] Verifikasi..."
if ($c5.status -eq "completed") { OK "Status: selesai" } else { NG "Status: $($c5.status)" }
if ($c5.explanation -match "fraud|kerugian|deteksi|channel|pencegahan") { OK "Analisis fraud ada" } else { NG "Tidak ada analisis" }
$img5 = @($c5.output_files | Where-Object { $_.type -eq "image" })
if ($img5.Count -gt 0) { OK "Grafik: $($img5.Count) PNG" } else { NG "Tidak ada grafik" }

Write-Host ""

# ============================================================================
# RINGKASAN
# ============================================================================
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  RINGKASAN HASIL UJI COBA"                    -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

$total = $pass + $fail
if ($fail -eq 0) {
    Write-Host "  SEMUA LULUS: $pass/$total" -ForegroundColor Green
} else {
    Write-Host "  HASIL: $pass lulus, $fail gagal (dari $total)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Use Case 1 (Anomali Transaksi):   $($c1.status)" -ForegroundColor $(if ($c1.status -eq "completed") {"Green"} else {"Red"})
Write-Host "  Use Case 2 (Risiko Kredit):        $($c2.status)" -ForegroundColor $(if ($c2.status -eq "completed") {"Green"} else {"Red"})
Write-Host "  Use Case 3 (Kinerja Cabang):       $($c3.status)" -ForegroundColor $(if ($c3.status -eq "completed") {"Green"} else {"Red"})
Write-Host "  Use Case 4 (Segmentasi Simpanan):  $($c4.status)" -ForegroundColor $(if ($c4.status -eq "completed") {"Green"} else {"Red"})
Write-Host "  Use Case 5 (Tren Fraud):           $($c5.status)" -ForegroundColor $(if ($c5.status -eq "completed") {"Green"} else {"Red"})
Write-Host ""
