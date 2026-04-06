"""Generate 5 large sample banking datasets in Bahasa Indonesia."""
import pandas as pd
import numpy as np
import os

np.random.seed(42)
out = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))), "sample-data")
os.makedirs(out, exist_ok=True)

cities = ["Jakarta", "Bandung", "Surabaya", "Medan", "Makassar", "Semarang",
          "Yogyakarta", "Denpasar", "Palembang", "Balikpapan"]

# ─── Dataset 1: Transaksi Nasabah (150 records) ───
n = 150
merchants = ["Tokopedia", "Shopee", "Indomaret", "Alfamart", "GrabFood", "GoFood",
             "PLN", "Telkomsel", "Unknown", "Transfer Bank", "DANA", "OVO",
             "Bukalapak", "Traveloka", "Tiket.com"]
channels = ["Online", "Offline", "Mobile Banking", "ATM", "Internet Banking"]
accounts = [f"A{str(i).zfill(4)}" for i in range(1, 31)]

amounts = np.concatenate([
    np.random.lognormal(12, 0.8, 130).astype(int),
    np.random.uniform(50_000_000, 200_000_000, 10).astype(int),
    np.random.uniform(500, 5000, 10).astype(int),
])
np.random.shuffle(amounts)

dates = pd.date_range("2025-01-01", "2025-03-31", periods=n)
df1 = pd.DataFrame({
    "transaction_id": [f"TXN{str(i).zfill(5)}" for i in range(1, n + 1)],
    "tanggal": dates.strftime("%Y-%m-%d"),
    "account_id": np.random.choice(accounts, n),
    "jumlah": amounts[:n],
    "merchant": np.random.choice(merchants, n),
    "channel": np.random.choice(channels, n),
    "kota": np.random.choice(cities, n),
    "kategori": np.random.choice(["Belanja", "Transfer", "Pembayaran", "Tarik Tunai", "Top Up", "Investasi"], n),
    "status": np.random.choice(["Berhasil", "Berhasil", "Berhasil", "Berhasil", "Gagal", "Pending"], n),
})
df1.to_csv(os.path.join(out, "transaksi_nasabah.csv"), index=False)
print(f"transaksi_nasabah.csv: {len(df1)} records")

# ─── Dataset 2: Portofolio Kredit (120 records) ───
n2 = 120
sectors = ["Manufaktur", "Perdagangan", "Konstruksi", "Pertanian", "Teknologi",
           "Perikanan", "Pertambangan", "Transportasi", "Perhotelan", "Kesehatan"]
regions = ["Jakarta", "Jawa Barat", "Jawa Timur", "Jawa Tengah", "Sumatera Utara",
           "Sulawesi Selatan", "Bali", "Kalimantan Timur", "Sumatera Selatan", "DI Yogyakarta"]

dpd_values = np.concatenate([
    np.zeros(50), np.random.choice([1, 7, 14, 21, 30], 25),
    np.random.choice([31, 45, 60], 20), np.random.choice([61, 75, 90], 15),
    np.random.choice([91, 120, 150, 180, 270, 360], 10),
]).astype(int)
np.random.shuffle(dpd_values)

company_names = []
prefixes = ["Maju", "Berkah", "Sejahtera", "Mandiri", "Sentosa", "Abadi", "Jaya", "Prima", "Karya", "Indah"]
suffixes = ["Utama", "Indonesia", "Nusantara", "Global", "Makmur", "Bersama", "Pratama", "Sejati"]
for _ in range(n2):
    company_names.append(f"PT {np.random.choice(prefixes)} {np.random.choice(suffixes)}")

df2 = pd.DataFrame({
    "loan_id": [f"LN{str(i).zfill(5)}" for i in range(1, n2 + 1)],
    "customer_id": [f"C{str(i).zfill(4)}" for i in np.random.randint(1, 80, n2)],
    "nama_debitur": company_names,
    "jumlah_pinjaman": (np.random.lognormal(20, 1, n2) / 1_000_000).astype(int) * 1_000_000,
    "sisa_pokok": (np.random.lognormal(19.5, 1, n2) / 1_000_000).astype(int) * 1_000_000,
    "suku_bunga": np.round(np.random.uniform(6, 18, n2), 2),
    "tenor_bulan": np.random.choice([12, 24, 36, 48, 60, 72, 84, 120], n2),
    "dpd": dpd_values[:n2],
    "sektor": np.random.choice(sectors, n2),
    "wilayah": np.random.choice(regions, n2),
    "tanggal_pencairan": pd.date_range("2022-01-01", "2024-12-31", periods=n2).strftime("%Y-%m-%d"),
    "jaminan": np.random.choice(["Properti", "Kendaraan", "Deposito", "Mesin", "Tanah", "Piutang", "Tanpa Jaminan"], n2),
})
df2.to_csv(os.path.join(out, "portofolio_kredit.csv"), index=False)
print(f"portofolio_kredit.csv: {len(df2)} records")

# ─── Dataset 3: Kinerja Cabang (100 records — 20 cabang x 5 bulan) ───
branch_cities = ["Jakarta Pusat", "Jakarta Selatan", "Jakarta Barat", "Bandung", "Surabaya",
                 "Medan", "Makassar", "Semarang", "Yogyakarta", "Denpasar",
                 "Palembang", "Malang", "Bogor", "Bekasi", "Tangerang",
                 "Solo", "Manado", "Padang", "Banjarmasin", "Pekanbaru"]
months = ["2025-01", "2025-02", "2025-03", "2025-04", "2025-05"]

rows3 = []
for i in range(20):
    base_rev = np.random.uniform(500_000_000, 3_000_000_000)
    base_acc = np.random.randint(50, 400)
    base_comp = np.random.randint(1, 25)
    for month in months:
        rows3.append({
            "branch_id": f"B{str(i + 1).zfill(3)}",
            "kota": branch_cities[i],
            "bulan": month,
            "pendapatan_bulanan": int(base_rev * np.random.uniform(0.85, 1.15)),
            "rekening_baru": int(base_acc * np.random.uniform(0.8, 1.2)),
            "jumlah_keluhan": int(base_comp * np.random.uniform(0.5, 2.0)),
            "jumlah_karyawan": np.random.randint(15, 80),
            "transaksi_digital": np.random.randint(5000, 50000),
            "transaksi_counter": np.random.randint(1000, 15000),
            "nps_score": round(np.random.uniform(20, 90), 1),
        })
df3 = pd.DataFrame(rows3)
df3.to_csv(os.path.join(out, "kinerja_cabang.csv"), index=False)
print(f"kinerja_cabang.csv: {len(df3)} records")

# ─── Dataset 4: Tabungan & Deposito (130 records) ───
n4 = 130
products = ["Tabungan Reguler", "Tabungan Bisnis", "Deposito 1 Bulan", "Deposito 3 Bulan",
            "Deposito 6 Bulan", "Deposito 12 Bulan", "Tabungan Haji", "Tabungan Pendidikan", "Giro"]
age_groups = ["18-25", "26-35", "36-45", "46-55", "56-65", "65+"]

df4 = pd.DataFrame({
    "account_id": [f"SAV{str(i).zfill(5)}" for i in range(1, n4 + 1)],
    "nama_nasabah": [f"Nasabah {chr(65 + i % 26)}{str(i).zfill(3)}" for i in range(n4)],
    "produk": np.random.choice(products, n4),
    "saldo": (np.random.lognormal(17, 1.5, n4) / 1000).astype(int) * 1000,
    "bunga_persen": np.round(np.random.uniform(1, 7, n4), 2),
    "tanggal_buka": pd.date_range("2020-01-01", "2025-03-31", periods=n4).strftime("%Y-%m-%d"),
    "kelompok_usia": np.random.choice(age_groups, n4, p=[0.15, 0.3, 0.25, 0.15, 0.1, 0.05]),
    "kota": np.random.choice(cities, n4),
    "status_aktif": np.random.choice(["Aktif", "Aktif", "Aktif", "Dormant", "Tutup"], n4),
    "kanal_pembukaan": np.random.choice(["Cabang", "Mobile App", "Internet Banking", "Agen"], n4),
    "frekuensi_transaksi_bulanan": np.random.poisson(8, n4),
})
df4.to_csv(os.path.join(out, "tabungan_deposito.csv"), index=False)
print(f"tabungan_deposito.csv: {len(df4)} records")

# ─── Dataset 5: Laporan Fraud (110 records) ───
n5 = 110
fraud_types = ["Skimming ATM", "Phishing", "Social Engineering", "Pemalsuan Dokumen",
               "Transaksi Tidak Sah", "SIM Swap", "Pencurian Identitas", "Money Mule"]
statuses = ["Terverifikasi", "Dalam Investigasi", "Ditolak", "Selesai - Ganti Rugi", "Selesai - Tidak Ganti Rugi"]

df5 = pd.DataFrame({
    "fraud_id": [f"FRD{str(i).zfill(5)}" for i in range(1, n5 + 1)],
    "tanggal_laporan": pd.date_range("2024-06-01", "2025-03-31", periods=n5).strftime("%Y-%m-%d"),
    "account_id": [f"A{str(i).zfill(4)}" for i in np.random.randint(1, 50, n5)],
    "jenis_fraud": np.random.choice(fraud_types, n5),
    "jumlah_kerugian": (np.random.lognormal(15, 1.2, n5) / 1000).astype(int) * 1000,
    "channel": np.random.choice(["ATM", "Mobile Banking", "Internet Banking", "Cabang", "EDC"], n5),
    "kota": np.random.choice(cities, n5),
    "status_investigasi": np.random.choice(statuses, n5),
    "waktu_deteksi_jam": np.round(np.random.exponential(24, n5), 1),
    "sumber_laporan": np.random.choice(["Nasabah", "Sistem Deteksi", "Cabang", "Call Center", "Pihak Ketiga"], n5),
    "resolved": np.random.choice([True, False], n5, p=[0.6, 0.4]),
})
df5.to_csv(os.path.join(out, "laporan_fraud.csv"), index=False)
print(f"laporan_fraud.csv: {len(df5)} records")

print("\nAll 5 datasets generated successfully!")
