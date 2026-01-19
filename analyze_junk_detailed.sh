#!/bin/bash

# Zaawansowany skrypt do szczegółowej analizy niepotrzebnych plików na macOS
# Zapisuje raport do pliku i wyświetla wyniki w konsoli
# Wersja 2.0 - z ulepszeniami wydajności i dodatkowymi funkcjami

# Sprawdzenie zależności
if ! command -v bc &> /dev/null; then
    echo "BŁĄD: Program 'bc' nie jest zainstalowany."
    echo "Zainstaluj go używając: brew install bc"
    exit 1
fi

# Domyślna konfiguracja
OLD_FILE_DAYS=90
UNUSED_FILE_DAYS=60
LARGE_FILE_SIZE_MB=100
MIN_FOLDER_SIZE_MB=10
QUICK_MODE=false
EXPORT_CSV=false
CSV_FILE=""

# Parsowanie argumentów CLI
while [[ $# -gt 0 ]]; do
    case $1 in
        --days=*)
            OLD_FILE_DAYS="${1#*=}"
            shift
            ;;
        --unused-days=*)
            UNUSED_FILE_DAYS="${1#*=}"
            shift
            ;;
        --min-size=*)
            MIN_FOLDER_SIZE_MB="${1#*=}"
            shift
            ;;
        --large-size=*)
            LARGE_FILE_SIZE_MB="${1#*=}"
            shift
            ;;
        --quick)
            QUICK_MODE=true
            shift
            ;;
        --csv)
            EXPORT_CSV=true
            shift
            ;;
        --csv-file=*)
            EXPORT_CSV=true
            CSV_FILE="${1#*=}"
            shift
            ;;
        --help|-h)
            echo "Użycie: $0 [opcje]"
            echo ""
            echo "Opcje:"
            echo "  --days=N              Pliki starsze niż N dni (domyślnie: 90)"
            echo "  --unused-days=N       Pliki nieużywane od N dni (domyślnie: 60)"
            echo "  --min-size=N          Minimalny rozmiar folderu w MB (domyślnie: 10)"
            echo "  --large-size=N        Próg dla dużych plików w MB (domyślnie: 100)"
            echo "  --quick               Tryb szybki (mniej szczegółowa analiza)"
            echo "  --csv                 Eksport wyników do CSV"
            echo "  --csv-file=PATH       Eksport do określonego pliku CSV"
            echo "  --help, -h            Wyświetl tę pomoc"
            exit 0
            ;;
        *)
            echo "Nieznana opcja: $1"
            echo "Użyj --help aby zobaczyć dostępne opcje"
            exit 1
            ;;
    esac
done

# Tworzenie nazwy pliku raportu z timestampem
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
REPORT_FILE="junk_analysis_${TIMESTAMP}.txt"
REPORT_DIR="${HOME}/Desktop"
FULL_REPORT_PATH="${REPORT_DIR}/${REPORT_FILE}"

# Tworzenie pliku CSV jeśli wymagane
if [ "$EXPORT_CSV" = true ]; then
    if [ -z "$CSV_FILE" ]; then
        CSV_FILE="${REPORT_DIR}/junk_analysis_${TIMESTAMP}.csv"
    fi
    # Nagłówek CSV
    echo "Kategoria,Ścieżka,Rozmiar (KB),Rozmiar (czytelny),Wiek (dni),Typ,Rekomendacja" > "$CSV_FILE"
fi

# Funkcja do zapisu do pliku i konsoli jednocześnie
log_output() {
    echo "$1" | tee -a "$FULL_REPORT_PATH"
}

# Funkcja do zapisu do CSV
log_csv() {
    if [ "$EXPORT_CSV" = true ]; then
        echo "$1" >> "$CSV_FILE"
    fi
}

# Funkcja do formatowania rozmiaru
format_size() {
    local size_kb=$1
    if [ -z "$size_kb" ] || [ "$size_kb" -eq 0 ]; then
        echo "0 B"
        return
    fi
    
    local size_mb=$(echo "scale=2; $size_kb/1024" | bc)
    local size_gb=$(echo "scale=2; $size_kb/1024/1024" | bc)
    
    if (( $(echo "$size_gb >= 1" | bc -l 2>/dev/null || echo 0) )); then
        printf "%.2f GB" "$size_gb"
    elif (( $(echo "$size_mb >= 1" | bc -l 2>/dev/null || echo 0) )); then
        printf "%.2f MB" "$size_mb"
    else
        printf "%.2f KB" "$size_kb"
    fi
}

# Funkcja do obliczania wieku pliku w dniach (data modyfikacji)
get_file_age() {
    local file_path="$1"
    if [ ! -e "$file_path" ]; then
        echo "0"
        return
    fi
    
    local file_time=$(stat -f "%m" "$file_path" 2>/dev/null || echo "0")
    local current_time=$(date +%s)
    local age_seconds=$((current_time - file_time))
    local age_days=$((age_seconds / 86400))
    echo "$age_days"
}

# Funkcja do obliczania ostatniego dostępu w dniach
get_file_access_age() {
    local file_path="$1"
    if [ ! -e "$file_path" ]; then
        echo "0"
        return
    fi
    
    # macOS używa stat -f "%a" dla ostatniego dostępu
    local file_time=$(stat -f "%a" "$file_path" 2>/dev/null || echo "0")
    local current_time=$(date +%s)
    local age_seconds=$((current_time - file_time))
    local age_days=$((age_seconds / 86400))
    echo "$age_days"
}

# Funkcja do sprawdzania czy plik jest typu "śmieci"
is_junk_type() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    local extension="${filename##*.}"
    
    # Lista rozszerzeń typowych dla "śmieci"
    case "$extension" in
        tmp|cache|log|old|bak|swp|temp|~|dmg|pkg)
            return 0
            ;;
    esac
    
    # Sprawdzanie nazwy pliku
    case "$filename" in
        *.tmp|*.cache|*.log|*.old|*.bak|*.swp|*.temp|*~|*.dmg|*.pkg|Thumbs.db|.DS_Store)
            return 0
            ;;
    esac
    
    return 1
}

# Funkcja do szczegółowej analizy folderu (zoptymalizowana)
analyze_folder_deep() {
    local folder_path="$1"
    local max_depth="${2:-2}"
    local min_size_mb="${3:-$MIN_FOLDER_SIZE_MB}"
    
    if [ ! -d "$folder_path" ]; then
        return
    fi
    
    # Używamy find z -exec du dla lepszej wydajności
    find "$folder_path" -maxdepth "$max_depth" -type d 2>/dev/null | while read -r dir; do
        if [ "$dir" = "$folder_path" ]; then
            continue
        fi
        
        # Używamy du bezpośrednio z find dla lepszej wydajności
        local size_kb=$(du -sk "$dir" 2>/dev/null | cut -f1)
        if [ -z "$size_kb" ] || [ "$size_kb" -eq 0 ]; then
            continue
        fi
        
        local size_mb=$(echo "scale=2; $size_kb/1024" | bc)
        
        # Tylko raportuj foldery większe niż próg
        if (( $(echo "$size_mb >= $min_size_mb" | bc -l 2>/dev/null || echo 0) )); then
            local rel_path="${dir#$folder_path/}"
            echo "${size_kb}|${dir}|${rel_path}"
        fi
    done | sort -t'|' -k1 -nr
}

# Funkcja do znajdowania starych plików (zoptymalizowana)
find_old_files() {
    local folder_path="$1"
    local min_age_days="${2:-$OLD_FILE_DAYS}"
    local min_size_mb="${3:-10}"
    local check_access="${4:-false}"
    
    if [ ! -d "$folder_path" ]; then
        return
    fi
    
    # Obliczamy timestamp dla porównania
    local cutoff_time=$(date -v-${min_age_days}d +%s 2>/dev/null || echo $(($(date +%s) - min_age_days * 86400)))
    
    find "$folder_path" -type f 2>/dev/null | while read -r file; do
        local file_time
        if [ "$check_access" = true ]; then
            file_time=$(stat -f "%a" "$file" 2>/dev/null || echo "0")
        else
            file_time=$(stat -f "%m" "$file" 2>/dev/null || echo "0")
        fi
        
        if [ "$file_time" -lt "$cutoff_time" ]; then
            local size_kb=$(du -sk "$file" 2>/dev/null | cut -f1)
            if [ -z "$size_kb" ] || [ "$size_kb" -eq 0 ]; then
                continue
            fi
            
            local size_mb=$(echo "scale=2; $size_kb/1024" | bc)
            if (( $(echo "$size_mb >= $min_size_mb" | bc -l 2>/dev/null || echo 0) )); then
                local age
                if [ "$check_access" = true ]; then
                    age=$(get_file_access_age "$file")
                else
                    age=$(get_file_age "$file")
                fi
                echo "${size_kb}|${file}|${age}"
            fi
        fi
    done | sort -t'|' -k1 -nr | head -n 20
}

# Funkcja do znajdowania dużych plików (zoptymalizowana)
find_large_files() {
    local folder_path="$1"
    local min_size_mb="${2:-$LARGE_FILE_SIZE_MB}"
    
    if [ ! -d "$folder_path" ]; then
        return
    fi
    
    local min_size_kb=$((min_size_mb * 1024))
    
    find "$folder_path" -type f -size +${min_size_kb}k 2>/dev/null | while read -r file; do
        local size_kb=$(du -sk "$file" 2>/dev/null | cut -f1)
        if [ -z "$size_kb" ] || [ "$size_kb" -eq 0 ]; then
            continue
        fi
        
        local age=$(get_file_age "$file")
        echo "${size_kb}|${file}|${age}"
    done | sort -t'|' -k1 -nr | head -n 20
}

# Funkcja do znajdowania pustych folderów
find_empty_folders() {
    local folder_path="$1"
    
    if [ ! -d "$folder_path" ]; then
        return
    fi
    
    find "$folder_path" -type d -empty 2>/dev/null | head -n 50
}

# Funkcja do znajdowania node_modules
find_node_modules() {
    local search_path="${1:-$HOME}"
    local max_depth="${2:-5}"
    
    find "$search_path" -maxdepth "$max_depth" -type d -name "node_modules" 2>/dev/null | head -n 20
}

# Funkcja do kategoryzacji
categorize_item() {
    local path="$1"
    local size_kb="$2"
    local age="$3"
    
    # Bezpieczne do usunięcia
    if [[ "$path" == *"/Caches"* ]] || \
       [[ "$path" == *"/Logs"* ]] || \
       [[ "$path" == *"/.Trash"* ]] || \
       [[ "$path" == *"/tmp"* ]] || \
       [[ "$path" == *"/Cache"* ]] || \
       [[ "$path" == *"/node_modules"* ]] || \
       [[ "$path" == *"/DerivedData"* ]] || \
       [[ "$path" == *"/CoreSimulator"* ]] || \
       is_junk_type "$path"; then
        echo "BEZPIECZNE"
        return
    fi
    
    # Wymagają przeglądu
    if [[ "$path" == *"/Downloads"* ]] || \
       [[ "$path" == *"/Application Support"* ]] || \
       [[ "$path" == *"/Desktop"* ]] || \
       [[ "$path" == *"/Xcode"* ]] || \
       [[ "$path" == *"/Developer"* ]]; then
        if [ "$age" -ge "$OLD_FILE_DAYS" ]; then
            echo "PRZEGLĄD"
        else
            echo "SPRAWDŹ"
        fi
        return
    fi
    
    # Potencjalnie niebezpieczne
    echo "OSTROŻNIE"
}

# Funkcja do analizy sekcji (refaktoryzacja duplikującego się kodu)
analyze_section() {
    local section_name="$1"
    local section_icon="$2"
    local paths_array_name="$3"
    local analysis_type="${4:-folders}"  # folders, old_files, large_files
    local min_size="${5:-$MIN_FOLDER_SIZE_MB}"
    local max_items="${6:-20}"
    
    log_output "${section_icon} ${section_name}"
    log_output "======================================================"
    log_output ""
    
    # Pobierz tablicę ścieżek
    eval "local paths=(\"\${${paths_array_name}[@]}\")"
    
    for path in "${paths[@]}"; do
        if [ ! -d "$path" ]; then
            continue
        fi
        
        log_output "🔍 Analizowanie: $path"
        log_output "----------------------------------------"
        
        local local_size=0
        local item_count=0
        
        case "$analysis_type" in
            folders)
                while IFS='|' read -r size_kb full_path rel_path; do
                    if [ -z "$size_kb" ]; then
                        continue
                    fi
                    
                    item_count=$((item_count + 1))
                    local_size=$((local_size + size_kb))
                    
                    local age=$(get_file_age "$full_path")
                    local category=$(categorize_item "$full_path" "$size_kb" "$age")
                    local formatted_size=$(format_size "$size_kb")
                    
                    log_output "  [$category] $formatted_size | ${age} dni | $rel_path"
                    
                    # Zapisz do CSV
                    log_csv "${section_name},${full_path},${size_kb},${formatted_size},${age},folder,${category}"
                    
                    # Aktualizuj globalne liczniki
                    case "$category" in
                        BEZPIECZNE)
                            TOTAL_SAFE_SIZE=$((TOTAL_SAFE_SIZE + size_kb))
                            ;;
                        PRZEGLĄD|SPRAWDŹ)
                            TOTAL_REVIEW_SIZE=$((TOTAL_REVIEW_SIZE + size_kb))
                            ;;
                        OSTROŻNIE)
                            TOTAL_CAUTION_SIZE=$((TOTAL_CAUTION_SIZE + size_kb))
                            ;;
                    esac
                    
                    if [ "$item_count" -ge "$max_items" ]; then
                        break
                    fi
                done < <(analyze_folder_deep "$path" 2 "$min_size")
                ;;
            old_files)
                while IFS='|' read -r size_kb file_path age; do
                    if [ -z "$size_kb" ]; then
                        continue
                    fi
                    
                    item_count=$((item_count + 1))
                    local_size=$((local_size + size_kb))
                    
                    local category=$(categorize_item "$file_path" "$size_kb" "$age")
                    local formatted_size=$(format_size "$size_kb")
                    local filename=$(basename "$file_path")
                    
                    log_output "  [$category] $formatted_size | ${age} dni | $filename"
                    
                    # Zapisz do CSV
                    log_csv "${section_name},${file_path},${size_kb},${formatted_size},${age},file,${category}"
                    
                    # Aktualizuj globalne liczniki
                    case "$category" in
                        BEZPIECZNE)
                            TOTAL_SAFE_SIZE=$((TOTAL_SAFE_SIZE + size_kb))
                            ;;
                        PRZEGLĄD|SPRAWDŹ)
                            TOTAL_REVIEW_SIZE=$((TOTAL_REVIEW_SIZE + size_kb))
                            ;;
                        OSTROŻNIE)
                            TOTAL_CAUTION_SIZE=$((TOTAL_CAUTION_SIZE + size_kb))
                            ;;
                    esac
                done < <(find_old_files "$path" "$OLD_FILE_DAYS" 10)
                ;;
            large_files)
                while IFS='|' read -r size_kb file_path age; do
                    if [ -z "$size_kb" ]; then
                        continue
                    fi
                    
                    item_count=$((item_count + 1))
                    local_size=$((local_size + size_kb))
                    
                    local category=$(categorize_item "$file_path" "$size_kb" "$age")
                    local formatted_size=$(format_size "$size_kb")
                    local filename=$(basename "$file_path")
                    
                    log_output "  [$category] $formatted_size | ${age} dni | $filename"
                    
                    # Zapisz do CSV
                    log_csv "${section_name},${file_path},${size_kb},${formatted_size},${age},file,${category}"
                    
                    # Aktualizuj globalne liczniki
                    case "$category" in
                        BEZPIECZNE)
                            TOTAL_SAFE_SIZE=$((TOTAL_SAFE_SIZE + size_kb))
                            ;;
                        PRZEGLĄD|SPRAWDŹ)
                            TOTAL_REVIEW_SIZE=$((TOTAL_REVIEW_SIZE + size_kb))
                            ;;
                        OSTROŻNIE)
                            TOTAL_CAUTION_SIZE=$((TOTAL_CAUTION_SIZE + size_kb))
                            ;;
                    esac
                done < <(find_large_files "$path" "$LARGE_FILE_SIZE_MB" | head -n "$max_items")
                ;;
        esac
        
        if [ "$item_count" -eq 0 ]; then
            log_output "  (Brak elementów do raportowania)"
        else
            log_output "  → Znaleziono $item_count elementów, łącznie: $(format_size $local_size)"
        fi
        
        log_output ""
    done
    
    log_output ""
}

# Inicjalizacja raportu
mkdir -p "$REPORT_DIR"
> "$FULL_REPORT_PATH"  # Tworzenie pustego pliku

log_output "🗑️  SZCZEGÓŁOWA ANALIZA NIEpotrzebnych PLIKÓW NA macOS v2.0"
log_output "======================================================"
log_output "Data analizy: $(date '+%Y-%m-%d %H:%M:%S')"
log_output "Użytkownik: $(whoami)"
log_output "Katalog domowy: $HOME"
log_output ""
log_output "Konfiguracja:"
log_output "  - Pliki starsze niż: ${OLD_FILE_DAYS} dni"
log_output "  - Pliki nieużywane od: ${UNUSED_FILE_DAYS} dni"
log_output "  - Duże pliki: powyżej ${LARGE_FILE_SIZE_MB} MB"
log_output "  - Minimalny rozmiar folderu: ${MIN_FOLDER_SIZE_MB} MB"
log_output "  - Tryb szybki: $([ "$QUICK_MODE" = true ] && echo "TAK" || echo "NIE")"
log_output "  - Eksport CSV: $([ "$EXPORT_CSV" = true ] && echo "TAK ($CSV_FILE)" || echo "NIE")"
log_output ""
log_output "Raport zapisany do: $FULL_REPORT_PATH"
if [ "$EXPORT_CSV" = true ]; then
    log_output "CSV zapisany do: $CSV_FILE"
fi
log_output ""
log_output "======================================================"
log_output ""

# Zmienne do podsumowania
TOTAL_SAFE_SIZE=0
TOTAL_REVIEW_SIZE=0
TOTAL_CAUTION_SIZE=0

# ============================================================
# SEKCJA 1: SZCZEGÓŁOWA ANALIZA CACHE
# ============================================================
CACHE_PATHS=(
    "$HOME/Library/Caches"
    "$HOME/.cache"
    "$HOME/.npm"
    "$HOME/.cursor-profiles"
    "$HOME/.chrome-cdp-profile"
    "$HOME/Library/Safari"
)

analyze_section "SEKCJA 1: ANALIZA CACHE" "📦" "CACHE_PATHS" "folders" 5

# ============================================================
# SEKCJA 2: SZCZEGÓŁOWA ANALIZA LOGÓW
# ============================================================
LOG_PATHS=(
    "$HOME/Library/Logs"
    "/var/log"
)

analyze_section "SEKCJA 2: ANALIZA LOGÓW" "📋" "LOG_PATHS" "folders" 5

# ============================================================
# SEKCJA 3: ANALIZA DOWNLOADS - STARE PLIKI
# ============================================================
if [ -d "$HOME/Downloads" ]; then
    log_output "📥 SEKCJA 3: ANALIZA DOWNLOADS (pliki starsze niż ${OLD_FILE_DAYS} dni)"
    log_output "======================================================"
    log_output ""
    
    DOWNLOADS_PATHS=("$HOME/Downloads")
    analyze_section "ANALIZA DOWNLOADS" "📥" "DOWNLOADS_PATHS" "old_files" 10
else
    log_output "📥 SEKCJA 3: ANALIZA DOWNLOADS"
    log_output "======================================================"
    log_output "  (Folder Downloads nie istnieje)"
    log_output ""
fi

# ============================================================
# SEKCJA 4: ANALIZA APPLICATION SUPPORT
# ============================================================
APP_SUPPORT_PATHS=(
    "$HOME/Library/Application Support"
)

analyze_section "SEKCJA 4: ANALIZA APPLICATION SUPPORT" "💾" "APP_SUPPORT_PATHS" "folders" 50 20

# ============================================================
# SEKCJA 5: ANALIZA KOSZA
# ============================================================
log_output "🗑️  SEKCJA 5: ANALIZA KOSZA"
log_output "======================================================"
log_output ""

TRASH_PATHS=(
    "$HOME/.Trash"
    "/.Trashes"
)

for trash_path in "${TRASH_PATHS[@]}"; do
    if [ ! -d "$trash_path" ]; then
        continue
    fi
    
    log_output "🔍 Analizowanie: $trash_path"
    log_output "----------------------------------------"
    
    local trash_size_kb=$(du -sk "$trash_path" 2>/dev/null | cut -f1)
    if [ -n "$trash_size_kb" ] && [ "$trash_size_kb" -gt 0 ]; then
        local trash_size=$(format_size "$trash_size_kb")
        local item_count=$(find "$trash_path" -type f 2>/dev/null | wc -l | tr -d ' ')
        
        log_output "  [BEZPIECZNE] $trash_size | $item_count plików"
        log_output "  → Można bezpiecznie opróżnić kosz"
        
        log_csv "KOSZ,${trash_path},${trash_size_kb},${trash_size},0,folder,BEZPIECZNE"
        
        TOTAL_SAFE_SIZE=$((TOTAL_SAFE_SIZE + trash_size_kb))
    else
        log_output "  (Kosz jest pusty)"
    fi
    
    log_output ""
done

# ============================================================
# SEKCJA 6: ANALIZA XCODE I DEVELOPER
# ============================================================
if [ "$QUICK_MODE" = false ]; then
    log_output "💻 SEKCJA 6: ANALIZA XCODE I DEVELOPER"
    log_output "======================================================"
    log_output ""
    
    XCODE_PATHS=(
        "$HOME/Library/Developer/Xcode/DerivedData"
        "$HOME/Library/Developer/Xcode/Archives"
        "$HOME/Library/Developer/CoreSimulator"
        "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
    )
    
    for xcode_path in "${XCODE_PATHS[@]}"; do
        if [ ! -d "$xcode_path" ]; then
            continue
        fi
        
        log_output "🔍 Analizowanie: $xcode_path"
        log_output "----------------------------------------"
        
        local xcode_size_kb=$(du -sk "$xcode_path" 2>/dev/null | cut -f1)
        if [ -n "$xcode_size_kb" ] && [ "$xcode_size_kb" -gt 0 ]; then
            local xcode_size=$(format_size "$xcode_size_kb")
            local age=$(get_file_age "$xcode_path")
            local category=$(categorize_item "$xcode_path" "$xcode_size_kb" "$age")
            
            log_output "  [$category] $xcode_size | ${age} dni"
            log_output "  → Można bezpiecznie wyczyścić (Xcode odbuduje w razie potrzeby)"
            
            log_csv "XCODE,${xcode_path},${xcode_size_kb},${xcode_size},${age},folder,${category}"
            
            if [ "$category" = "BEZPIECZNE" ] || [ "$category" = "PRZEGLĄD" ]; then
                TOTAL_SAFE_SIZE=$((TOTAL_SAFE_SIZE + xcode_size_kb))
            else
                TOTAL_REVIEW_SIZE=$((TOTAL_REVIEW_SIZE + xcode_size_kb))
            fi
        else
            log_output "  (Folder nie istnieje lub jest pusty)"
        fi
        
        log_output ""
    done
fi

# ============================================================
# SEKCJA 7: ANALIZA NODE_MODULES
# ============================================================
if [ "$QUICK_MODE" = false ]; then
    log_output "📦 SEKCJA 7: ANALIZA NODE_MODULES"
    log_output "======================================================"
    log_output ""
    
    log_output "🔍 Wyszukiwanie folderów node_modules..."
    log_output "----------------------------------------"
    
    local node_modules_count=0
    local node_modules_total=0
    
    while IFS= read -r node_path; do
        if [ -z "$node_path" ]; then
            continue
        fi
        
        node_modules_count=$((node_modules_count + 1))
        local node_size_kb=$(du -sk "$node_path" 2>/dev/null | cut -f1)
        
        if [ -n "$node_size_kb" ] && [ "$node_size_kb" -gt 0 ]; then
            node_modules_total=$((node_modules_total + node_size_kb))
            local node_size=$(format_size "$node_size_kb")
            local rel_path="${node_path#$HOME/}"
            
            log_output "  [BEZPIECZNE] $node_size | $rel_path"
            
            log_csv "NODE_MODULES,${node_path},${node_size_kb},${node_size},0,folder,BEZPIECZNE"
            
            TOTAL_SAFE_SIZE=$((TOTAL_SAFE_SIZE + node_size_kb))
        fi
        
        if [ "$node_modules_count" -ge 20 ]; then
            break
        fi
    done < <(find_node_modules "$HOME" 5)
    
    if [ "$node_modules_count" -eq 0 ]; then
        log_output "  (Nie znaleziono folderów node_modules)"
    else
        log_output "  → Znaleziono $node_modules_count folderów node_modules, łącznie: $(format_size $node_modules_total)"
    fi
    
    log_output ""
fi

# ============================================================
# SEKCJA 8: ANALIZA DOCKER
# ============================================================
if [ "$QUICK_MODE" = false ]; then
    log_output "🐳 SEKCJA 8: ANALIZA DOCKER"
    log_output "======================================================"
    log_output ""
    
    DOCKER_PATHS=(
        "$HOME/.docker"
        "$HOME/Library/Containers/com.docker.docker"
    )
    
    for docker_path in "${DOCKER_PATHS[@]}"; do
        if [ ! -d "$docker_path" ]; then
            continue
        fi
        
        log_output "🔍 Analizowanie: $docker_path"
        log_output "----------------------------------------"
        
        local docker_size_kb=$(du -sk "$docker_path" 2>/dev/null | cut -f1)
        if [ -n "$docker_size_kb" ] && [ "$docker_size_kb" -gt 0 ]; then
            local docker_size=$(format_size "$docker_size_kb")
            local age=$(get_file_age "$docker_path")
            
            log_output "  [PRZEGLĄD] $docker_size | ${age} dni"
            log_output "  → Sprawdź nieużywane obrazy: docker system prune -a"
            
            log_csv "DOCKER,${docker_path},${docker_size_kb},${docker_size},${age},folder,PRZEGLĄD"
            
            TOTAL_REVIEW_SIZE=$((TOTAL_REVIEW_SIZE + docker_size_kb))
        else
            log_output "  (Folder nie istnieje lub jest pusty)"
        fi
        
        log_output ""
    done
fi

# ============================================================
# SEKCJA 9: ANALIZA HOMEBREW
# ============================================================
if [ "$QUICK_MODE" = false ]; then
    log_output "🍺 SEKCJA 9: ANALIZA HOMEBREW"
    log_output "======================================================"
    log_output ""
    
    BREW_PATHS=(
        "/usr/local/Cellar"
        "/opt/homebrew/Cellar"
        "/usr/local/var/cache"
        "/opt/homebrew/var/cache"
    )
    
    for brew_path in "${BREW_PATHS[@]}"; do
        if [ ! -d "$brew_path" ]; then
            continue
        fi
        
        log_output "🔍 Analizowanie: $brew_path"
        log_output "----------------------------------------"
        
        local brew_size_kb=$(du -sk "$brew_path" 2>/dev/null | cut -f1)
        if [ -n "$brew_size_kb" ] && [ "$brew_size_kb" -gt 0 ]; then
            local brew_size=$(format_size "$brew_size_kb")
            local age=$(get_file_age "$brew_path")
            
            log_output "  [PRZEGLĄD] $brew_size | ${age} dni"
            log_output "  → Sprawdź stare wersje: brew cleanup --prune=all"
            
            log_csv "HOMEBREW,${brew_path},${brew_size_kb},${brew_size},${age},folder,PRZEGLĄD"
            
            TOTAL_REVIEW_SIZE=$((TOTAL_REVIEW_SIZE + brew_size_kb))
        else
            log_output "  (Folder nie istnieje lub jest pusty)"
        fi
        
        log_output ""
    done
fi

# ============================================================
# SEKCJA 10: DUŻE PLIKI W TYPOWYCH LOKALIZACJACH
# ============================================================
LARGE_FILE_PATHS=(
    "$HOME/Library/Caches"
    "$HOME/Library/Logs"
    "$HOME/Downloads"
    "$HOME/.npm"
    "$HOME/.cache"
)

analyze_section "SEKCJA 10: DUŻE PLIKI" "📊" "LARGE_FILE_PATHS" "large_files" "$LARGE_FILE_SIZE_MB" 10

# ============================================================
# SEKCJA 11: PUSTE FOLDERY
# ============================================================
log_output "📁 SEKCJA 11: PUSTE FOLDERY"
log_output "======================================================"
log_output ""

EMPTY_FOLDER_PATHS=(
    "$HOME/Library/Caches"
    "$HOME/Library/Logs"
    "$HOME/Downloads"
    "$HOME/Desktop"
)

empty_count=0
for empty_path in "${EMPTY_FOLDER_PATHS[@]}"; do
    if [ ! -d "$empty_path" ]; then
        continue
    fi
    
    while IFS= read -r empty_dir; do
        if [ -n "$empty_dir" ]; then
            empty_count=$((empty_count + 1))
            if [ "$empty_count" -le 20 ]; then
                local rel_path="${empty_dir#$empty_path/}"
                log_output "  $rel_path"
                log_csv "PUSTE_FOLDERY,${empty_dir},0,0 B,0,folder,BEZPIECZNE"
            fi
        fi
    done < <(find_empty_folders "$empty_path")
done

if [ "$empty_count" -eq 0 ]; then
    log_output "  (Brak pustych folderów)"
elif [ "$empty_count" -gt 20 ]; then
    log_output "  ... i $((empty_count - 20)) więcej"
    log_output "  → Łącznie znaleziono $empty_count pustych folderów"
else
    log_output "  → Łącznie znaleziono $empty_count pustych folderów"
fi

log_output ""

# ============================================================
# SEKCJA 12: PLIKI NIEUŻYWANE (ostatni dostęp)
# ============================================================
if [ "$QUICK_MODE" = false ] && [ "$UNUSED_FILE_DAYS" -gt 0 ]; then
    log_output "⏰ SEKCJA 12: PLIKI NIEUŻYWANE (ostatni dostęp > ${UNUSED_FILE_DAYS} dni)"
    log_output "======================================================"
    log_output ""
    
    UNUSED_PATHS=(
        "$HOME/Downloads"
        "$HOME/Desktop"
        "$HOME/Documents"
    )
    
    for unused_path in "${UNUSED_PATHS[@]}"; do
        if [ ! -d "$unused_path" ]; then
            continue
        fi
        
        log_output "🔍 Analizowanie nieużywanych plików w: $unused_path"
        log_output "----------------------------------------"
        
        local unused_count=0
        local unused_total=0
        
        while IFS='|' read -r size_kb file_path age; do
            if [ -z "$size_kb" ]; then
                continue
            fi
            
            unused_count=$((unused_count + 1))
            unused_total=$((unused_total + size_kb))
            
            local category=$(categorize_item "$file_path" "$size_kb" "$age")
            local formatted_size=$(format_size "$size_kb")
            local filename=$(basename "$file_path")
            
            log_output "  [$category] $formatted_size | ${age} dni (ostatni dostęp) | $filename"
            
            log_csv "NIEUŻYWANE,${file_path},${size_kb},${formatted_size},${age},file,${category}"
            
            case "$category" in
                BEZPIECZNE)
                    TOTAL_SAFE_SIZE=$((TOTAL_SAFE_SIZE + size_kb))
                    ;;
                PRZEGLĄD|SPRAWDŹ)
                    TOTAL_REVIEW_SIZE=$((TOTAL_REVIEW_SIZE + size_kb))
                    ;;
            esac
            
            if [ "$unused_count" -ge 15 ]; then
                break
            fi
        done < <(find_old_files "$unused_path" "$UNUSED_FILE_DAYS" 10 true)
        
        if [ "$unused_count" -eq 0 ]; then
            log_output "  (Brak nieużywanych plików)"
        else
            log_output "  → Znaleziono $unused_count plików, łącznie: $(format_size $unused_total)"
        fi
        
        log_output ""
    done
fi

# ============================================================
# PODSUMOWANIE
# ============================================================
log_output "======================================================"
log_output "📊 PODSUMOWANIE ANALIZY"
log_output "======================================================"
log_output ""

TOTAL_SIZE=$((TOTAL_SAFE_SIZE + TOTAL_REVIEW_SIZE + TOTAL_CAUTION_SIZE))

log_output "Kategoryzacja znalezionych plików:"
log_output "  🟢 BEZPIECZNE do usunięcia:     $(format_size $TOTAL_SAFE_SIZE)"
log_output "  🟡 WYMAGAJĄ PRZEGLĄDU:          $(format_size $TOTAL_REVIEW_SIZE)"
log_output "  🔴 WYMAGAJĄ OSTROŻNOŚCI:        $(format_size $TOTAL_CAUTION_SIZE)"
log_output "  ─────────────────────────────────────────────"
log_output "  📦 ŁĄCZNIE:                     $(format_size $TOTAL_SIZE)"
log_output ""

log_output "💡 REKOMENDACJE:"
log_output ""

if [ "$TOTAL_SAFE_SIZE" -gt 0 ]; then
    log_output "✅ MOŻNA BEZPIECZNIE USUNĄĆ ($(format_size $TOTAL_SAFE_SIZE)):"
    log_output "   • Cache: ~/Library/Caches - można wyczyścić cały folder"
    log_output "   • Logi: ~/Library/Logs - można wyczyścić cały folder"
    log_output "   • Kosz: ~/.Trash - opróżnij kosz"
    log_output "   • Tymczasowe pliki: ~/.cache, ~/.npm - sprawdź zawartość"
    log_output "   • node_modules: można bezpiecznie usunąć (npm/yarn odbuduje)"
    log_output "   • Xcode DerivedData: można bezpiecznie wyczyścić"
    log_output ""
fi

if [ "$TOTAL_REVIEW_SIZE" -gt 0 ]; then
    log_output "⚠️  WYMAGAJĄ PRZEGLĄDU ($(format_size $TOTAL_REVIEW_SIZE)):"
    log_output "   • Downloads: ~/Downloads - sprawdź stare pliki"
    log_output "   • Desktop: ~/Desktop - sprawdź nieużywane pliki"
    log_output "   • Application Support: sprawdź foldery starych aplikacji"
    log_output "   • Docker: sprawdź nieużywane obrazy (docker system prune -a)"
    log_output "   • Homebrew: sprawdź stare wersje (brew cleanup --prune=all)"
    log_output ""
fi

if [ "$TOTAL_CAUTION_SIZE" -gt 0 ]; then
    log_output "🔴 WYMAGAJĄ OSTROŻNOŚCI ($(format_size $TOTAL_CAUTION_SIZE)):"
    log_output "   • Application Support: mogą zawierać ważne dane aplikacji"
    log_output "   • Przed usunięciem sprawdź czy aplikacja jest nadal używana"
    log_output ""
fi

log_output "======================================================"
log_output "✅ Analiza zakończona!"
log_output "📄 Pełny raport zapisany do: $FULL_REPORT_PATH"
if [ "$EXPORT_CSV" = true ]; then
    log_output "📊 Raport CSV zapisany do: $CSV_FILE"
fi
log_output "======================================================"
