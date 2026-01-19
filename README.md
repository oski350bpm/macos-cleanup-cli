# 🗑️ macOS CleanUp - CLI Manager

Zaawansowane narzędzie CLI do analizy, zarządzania i czyszczenia niepotrzebnych plików na macOS.

## ✨ Funkcje

- 🔍 **Szczegółowa analiza** - identyfikacja niepotrzebnych plików na podstawie wieku, typu, rozmiaru i ostatniego dostępu
- 🗑️ **Interaktywne usuwanie** - bezpieczne czyszczenie cache, logów, npm, puppeteer i innych
- 💾 **Backup** - kopiowanie plików do dysku zewnętrznego
- 🔄 **Sync** - synchronizacja folderów z dyskiem zewnętrznym
- ⚡ **Szybkie czyszczenie** - jednoklikowe usuwanie bezpiecznych plików
- 📊 **Raporty CSV** - eksport wyników do plików CSV
- ⚙️ **Konfiguracja** - elastyczne ustawienia przez plik konfiguracyjny

## 📋 Wymagania

- macOS
- `bc` (kalkulator) - zainstaluj: `brew install bc`
- `rsync` (opcjonalnie, dla sync) - zwykle preinstalowany

## 🚀 Instalacja

1. Sklonuj repozytorium:
```bash
git clone https://github.com/TWOJE_USERNAME/macos-cleanup-cli.git
cd macos-cleanup-cli
```

2. Nadaj uprawnienia wykonywania:
```bash
chmod +x analyze_junk_detailed.sh junk_manager.sh tests/*.sh
```

3. Skonfiguruj (opcjonalnie):
```bash
nano junk_manager.conf
```

## 📖 Użycie

### Interaktywny menedżer

```bash
./junk_manager.sh
```

### Bezpośrednia analiza

```bash
./analyze_junk_detailed.sh [opcje]
```

**Opcje:**
- `--days=N` - Pliki starsze niż N dni (domyślnie: 90)
- `--unused-days=N` - Pliki nieużywane od N dni (domyślnie: 60)
- `--min-size=N` - Minimalny rozmiar folderu w MB (domyślnie: 10)
- `--large-size=N` - Próg dla dużych plików w MB (domyślnie: 100)
- `--quick` - Tryb szybki (mniej szczegółowa analiza)
- `--csv` - Eksport wyników do CSV
- `--csv-file=PATH` - Eksport do określonego pliku CSV
- `--help` - Wyświetl pomoc

## ⚙️ Konfiguracja

Edytuj plik `junk_manager.conf`:

```bash
EXTERNAL_DRIVE="/Volumes/KINGSTON"
BACKUP_FOLDER="Backups"
OLD_FILE_DAYS=90
UNUSED_FILE_DAYS=60
LARGE_FILE_SIZE_MB=100
MIN_FOLDER_SIZE_MB=10
QUICK_MODE=false
EXPORT_CSV=true
```

## 🧪 Testy

```bash
./tests/run_all_tests.sh
```

## 📄 Licencja

MIT License

