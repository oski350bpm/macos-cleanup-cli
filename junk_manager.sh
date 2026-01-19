#!/bin/bash

# ============================================================
# JUNK MANAGER - Interaktywny menedżer plików
# Wersja: 1.0
# Funkcje: analiza, usuwanie, backup, sync
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/junk_manager.conf"
ANALYZE_SCRIPT="$SCRIPT_DIR/analyze_junk_detailed.sh"

# Domyślna konfiguracja
EXTERNAL_DRIVE="/Volumes/KINGSTON"
BACKUP_FOLDER="Backups"
OLD_FILE_DAYS=90
UNUSED_FILE_DAYS=60
LARGE_FILE_SIZE_MB=100
MIN_FOLDER_SIZE_MB=10
QUICK_MODE=false
EXPORT_CSV=true
REPORT_DIR="$HOME/Desktop"
AUTO_CONFIRM=false
COLOR_OUTPUT=true

# Kolory
setup_colors() {
    if [ "$COLOR_OUTPUT" = true ]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        PURPLE='\033[0;35m'
        CYAN='\033[0;36m'
        WHITE='\033[1;37m'
        GRAY='\033[0;90m'
        NC='\033[0m' # No Color
        BOLD='\033[1m'
    else
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        PURPLE=''
        CYAN=''
        WHITE=''
        GRAY=''
        NC=''
        BOLD=''
    fi
}

# Wczytaj konfigurację
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # Wczytaj tylko linie z przypisaniem (bez komentarzy)
        while IFS='=' read -r key value; do
            # Pomiń komentarze i puste linie
            [[ "$key" =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue
            
            # Usuń białe znaki
            key=$(echo "$key" | tr -d ' ')
            value=$(echo "$value" | tr -d '"' | tr -d "'")
            
            case "$key" in
                EXTERNAL_DRIVE) EXTERNAL_DRIVE="$value" ;;
                BACKUP_FOLDER) BACKUP_FOLDER="$value" ;;
                OLD_FILE_DAYS) OLD_FILE_DAYS="$value" ;;
                UNUSED_FILE_DAYS) UNUSED_FILE_DAYS="$value" ;;
                LARGE_FILE_SIZE_MB) LARGE_FILE_SIZE_MB="$value" ;;
                MIN_FOLDER_SIZE_MB) MIN_FOLDER_SIZE_MB="$value" ;;
                QUICK_MODE) QUICK_MODE="$value" ;;
                EXPORT_CSV) EXPORT_CSV="$value" ;;
                REPORT_DIR) REPORT_DIR="${value//\$HOME/$HOME}" ;;
                AUTO_CONFIRM) AUTO_CONFIRM="$value" ;;
                COLOR_OUTPUT) COLOR_OUTPUT="$value" ;;
            esac
        done < "$CONFIG_FILE"
    fi
    setup_colors
}

# Zapisz konfigurację
save_config() {
    cat > "$CONFIG_FILE" << EOF
# Konfiguracja Junk Manager
# Edytuj ten plik lub użyj opcji "Ustawienia" w menu

# Ścieżka do dysku zewnętrznego (backup/sync)
EXTERNAL_DRIVE="$EXTERNAL_DRIVE"

# Folder na backupy na dysku zewnętrznym
BACKUP_FOLDER="$BACKUP_FOLDER"

# Parametry analizy
OLD_FILE_DAYS=$OLD_FILE_DAYS
UNUSED_FILE_DAYS=$UNUSED_FILE_DAYS
LARGE_FILE_SIZE_MB=$LARGE_FILE_SIZE_MB
MIN_FOLDER_SIZE_MB=$MIN_FOLDER_SIZE_MB

# Tryb szybki (true/false)
QUICK_MODE=$QUICK_MODE

# Eksport CSV (true/false)
EXPORT_CSV=$EXPORT_CSV

# Katalog na raporty
REPORT_DIR="$REPORT_DIR"

# Automatyczne potwierdzanie (true = bez pytania, false = z potwierdzeniem)
AUTO_CONFIRM=$AUTO_CONFIRM

# Kolorowe wyjście (true/false)
COLOR_OUTPUT=$COLOR_OUTPUT
EOF
    echo -e "${GREEN}✓ Konfiguracja zapisana${NC}"
}

# Wyświetl nagłówek
show_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}           ${BOLD}🗑️  JUNK MANAGER - Menedżer plików${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              ${GRAY}Analiza • Usuwanie • Backup${NC}                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Wyświetl status dysku zewnętrznego
show_drive_status() {
    if [ -d "$EXTERNAL_DRIVE" ]; then
        local free_space=$(df -h "$EXTERNAL_DRIVE" 2>/dev/null | tail -1 | awk '{print $4}')
        local total_space=$(df -h "$EXTERNAL_DRIVE" 2>/dev/null | tail -1 | awk '{print $2}')
        echo -e "${GREEN}✓ Dysk zewnętrzny:${NC} $EXTERNAL_DRIVE"
        echo -e "  ${GRAY}Wolne: ${free_space} / ${total_space}${NC}"
    else
        echo -e "${RED}✗ Dysk zewnętrzny niedostępny:${NC} $EXTERNAL_DRIVE"
    fi
    echo ""
}

# Formatowanie rozmiaru
format_size() {
    local size_kb=$1
    if [ -z "$size_kb" ] || [ "$size_kb" -eq 0 ]; then
        echo "0 B"
        return
    fi
    
    if [ "$size_kb" -ge 1048576 ]; then
        echo "$(echo "scale=2; $size_kb/1048576" | bc) GB"
    elif [ "$size_kb" -ge 1024 ]; then
        echo "$(echo "scale=2; $size_kb/1024" | bc) MB"
    else
        echo "${size_kb} KB"
    fi
}

# Potwierdzenie akcji
confirm_action() {
    local message="$1"
    
    if [ "$AUTO_CONFIRM" = true ]; then
        return 0
    fi
    
    echo -e "${YELLOW}⚠️  $message${NC}"
    read -p "Czy kontynuować? (t/n): " choice
    case "$choice" in
        t|T|tak|TAK|y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

# ============================================================
# MENU GŁÓWNE
# ============================================================

show_main_menu() {
    show_header
    show_drive_status
    
    echo -e "${WHITE}MENU GŁÓWNE${NC}"
    echo -e "${GRAY}─────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} 🔍 Uruchom analizę"
    echo -e "  ${CYAN}2)${NC} 📋 Pokaż ostatni raport"
    echo -e "  ${CYAN}3)${NC} 🗑️  Usuwanie plików (interaktywne)"
    echo -e "  ${CYAN}4)${NC} 💾 Backup do dysku zewnętrznego"
    echo -e "  ${CYAN}5)${NC} 🔄 Sync z dyskiem zewnętrznym"
    echo -e "  ${CYAN}6)${NC} ⚡ Szybkie czyszczenie (bezpieczne)"
    echo -e "  ${CYAN}7)${NC} ⚙️  Ustawienia"
    echo -e "  ${CYAN}8)${NC} ❓ Pomoc"
    echo -e "  ${CYAN}0)${NC} 🚪 Wyjście"
    echo ""
    echo -e "${GRAY}─────────────────────────────────────────${NC}"
    read -p "Wybierz opcję [0-8]: " choice
    
    case $choice in
        1) run_analysis ;;
        2) show_last_report ;;
        3) interactive_delete_menu ;;
        4) backup_menu ;;
        5) sync_menu ;;
        6) quick_cleanup ;;
        7) settings_menu ;;
        8) show_help ;;
        0) exit 0 ;;
        *) echo -e "${RED}Nieprawidłowa opcja${NC}"; sleep 1 ;;
    esac
}

# ============================================================
# ANALIZA
# ============================================================

run_analysis() {
    show_header
    echo -e "${BLUE}🔍 Uruchamianie analizy...${NC}"
    echo ""
    
    local args=""
    args+=" --days=$OLD_FILE_DAYS"
    args+=" --unused-days=$UNUSED_FILE_DAYS"
    args+=" --min-size=$MIN_FOLDER_SIZE_MB"
    args+=" --large-size=$LARGE_FILE_SIZE_MB"
    
    if [ "$QUICK_MODE" = true ]; then
        args+=" --quick"
    fi
    
    if [ "$EXPORT_CSV" = true ]; then
        args+=" --csv"
    fi
    
    if [ -f "$ANALYZE_SCRIPT" ]; then
        bash "$ANALYZE_SCRIPT" $args
    else
        echo -e "${RED}Błąd: Skrypt analizy nie znaleziony: $ANALYZE_SCRIPT${NC}"
    fi
    
    echo ""
    read -p "Naciśnij Enter aby kontynuować..."
}

# ============================================================
# OSTATNI RAPORT
# ============================================================

show_last_report() {
    show_header
    
    local last_report=$(ls -t "$REPORT_DIR"/junk_analysis_*.txt 2>/dev/null | head -1)
    
    if [ -z "$last_report" ]; then
        echo -e "${YELLOW}Brak raportów. Uruchom najpierw analizę.${NC}"
    else
        echo -e "${GREEN}Ostatni raport: ${NC}$last_report"
        echo ""
        
        # Wyświetl podsumowanie
        grep -A 20 "PODSUMOWANIE ANALIZY" "$last_report" | head -25
    fi
    
    echo ""
    read -p "Naciśnij Enter aby kontynuować..."
}

# ============================================================
# INTERAKTYWNE USUWANIE
# ============================================================

interactive_delete_menu() {
    while true; do
        show_header
        echo -e "${WHITE}🗑️  INTERAKTYWNE USUWANIE${NC}"
        echo -e "${GRAY}─────────────────────────────────────────${NC}"
        echo ""
        echo -e "  ${CYAN}1)${NC} 🧹 Wyczyść cache aplikacji"
        echo -e "  ${CYAN}2)${NC} 📋 Wyczyść logi"
        echo -e "  ${CYAN}3)${NC} 📦 Wyczyść npm cache"
        echo -e "  ${CYAN}4)${NC} 🎭 Wyczyść Puppeteer/Playwright"
        echo -e "  ${CYAN}5)${NC} 🗑️  Opróżnij kosz"
        echo -e "  ${CYAN}6)${NC} 📥 Przejrzyj Downloads"
        echo -e "  ${CYAN}7)${NC} 🔧 Wyczyść Cursor cache"
        echo -e "  ${CYAN}8)${NC} ⚡ Wyczyść wszystko bezpieczne"
        echo -e "  ${CYAN}0)${NC} ← Powrót"
        echo ""
        read -p "Wybierz opcję [0-8]: " choice
        
        case $choice in
            1) clean_app_cache ;;
            2) clean_logs ;;
            3) clean_npm_cache ;;
            4) clean_puppeteer ;;
            5) empty_trash ;;
            6) browse_downloads ;;
            7) clean_cursor_cache ;;
            8) quick_cleanup ;;
            0) return ;;
        esac
    done
}

# Czyszczenie cache aplikacji
clean_app_cache() {
    show_header
    echo -e "${WHITE}🧹 CACHE APLIKACJI${NC}"
    echo ""
    
    local cache_dirs=(
        "$HOME/Library/Caches/Google"
        "$HOME/Library/Caches/Firefox"
        "$HOME/Library/Caches/com.spotify.client"
        "$HOME/Library/Caches/Ableton"
        "$HOME/Library/Caches/ms-playwright"
        "$HOME/Library/Caches/pip"
        "$HOME/Library/Caches/Homebrew"
        "$HOME/Library/Caches/com.todesktop.230313mzl4w4u92.ShipIt"
        "$HOME/Library/Caches/notion.id.ShipIt"
        "$HOME/Library/Caches/canva-updater"
    )
    
    local total_size=0
    local dirs_to_clean=()
    
    echo -e "${GRAY}Znalezione foldery cache:${NC}"
    echo ""
    
    local idx=1
    for dir in "${cache_dirs[@]}"; do
        if [ -d "$dir" ]; then
            local size_kb=$(du -sk "$dir" 2>/dev/null | cut -f1)
            local size_formatted=$(format_size "$size_kb")
            local name=$(basename "$dir")
            
            echo -e "  ${CYAN}$idx)${NC} $name ${GRAY}($size_formatted)${NC}"
            dirs_to_clean+=("$dir")
            total_size=$((total_size + size_kb))
            idx=$((idx + 1))
        fi
    done
    
    echo ""
    echo -e "  ${YELLOW}Łącznie: $(format_size $total_size)${NC}"
    echo ""
    echo -e "  ${CYAN}a)${NC} Wyczyść wszystkie"
    echo -e "  ${CYAN}0)${NC} Powrót"
    echo ""
    read -p "Wybierz opcję: " choice
    
    if [ "$choice" = "0" ]; then
        return
    elif [ "$choice" = "a" ] || [ "$choice" = "A" ]; then
        if confirm_action "Usunąć wszystkie foldery cache? ($(format_size $total_size))"; then
            for dir in "${dirs_to_clean[@]}"; do
                echo -e "${GRAY}Usuwanie: $dir${NC}"
                rm -rf "$dir"
            done
            echo -e "${GREEN}✓ Cache wyczyszczony!${NC}"
        fi
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#dirs_to_clean[@]}" ]; then
        local dir="${dirs_to_clean[$((choice-1))]}"
        local size_kb=$(du -sk "$dir" 2>/dev/null | cut -f1)
        if confirm_action "Usunąć $(basename "$dir")? ($(format_size $size_kb))"; then
            rm -rf "$dir"
            echo -e "${GREEN}✓ Usunięto!${NC}"
        fi
    fi
    
    read -p "Naciśnij Enter aby kontynuować..."
}

# Czyszczenie logów
clean_logs() {
    show_header
    echo -e "${WHITE}📋 CZYSZCZENIE LOGÓW${NC}"
    echo ""
    
    local log_dir="$HOME/Library/Logs"
    local size_kb=$(du -sk "$log_dir" 2>/dev/null | cut -f1)
    
    echo -e "Folder logów: $log_dir"
    echo -e "Rozmiar: $(format_size $size_kb)"
    echo ""
    
    if confirm_action "Wyczyścić wszystkie logi?"; then
        rm -rf "$log_dir"/*
        echo -e "${GREEN}✓ Logi wyczyszczone!${NC}"
    fi
    
    read -p "Naciśnij Enter aby kontynuować..."
}

# Czyszczenie npm cache
clean_npm_cache() {
    show_header
    echo -e "${WHITE}📦 NPM CACHE${NC}"
    echo ""
    
    local npm_cache="$HOME/.npm"
    local npx_cache="$HOME/.npm/_npx"
    
    if [ -d "$npm_cache" ]; then
        local size_kb=$(du -sk "$npm_cache" 2>/dev/null | cut -f1)
        echo -e "NPM cache: $(format_size $size_kb)"
    fi
    
    if [ -d "$npx_cache" ]; then
        local npx_size_kb=$(du -sk "$npx_cache" 2>/dev/null | cut -f1)
        echo -e "NPX cache: $(format_size $npx_size_kb)"
    fi
    
    echo ""
    echo -e "  ${CYAN}1)${NC} Wyczyść cały npm cache (npm cache clean --force)"
    echo -e "  ${CYAN}2)${NC} Usuń tylko npx cache"
    echo -e "  ${CYAN}0)${NC} Powrót"
    echo ""
    read -p "Wybierz opcję: " choice
    
    case $choice in
        1)
            if confirm_action "Wyczyścić cały npm cache?"; then
                npm cache clean --force 2>/dev/null
                echo -e "${GREEN}✓ NPM cache wyczyszczony!${NC}"
            fi
            ;;
        2)
            if confirm_action "Usunąć npx cache?"; then
                rm -rf "$npx_cache"
                echo -e "${GREEN}✓ NPX cache usunięty!${NC}"
            fi
            ;;
    esac
    
    read -p "Naciśnij Enter aby kontynuować..."
}

# Czyszczenie Puppeteer
clean_puppeteer() {
    show_header
    echo -e "${WHITE}🎭 PUPPETEER/PLAYWRIGHT CACHE${NC}"
    echo ""
    
    local dirs=(
        "$HOME/.cache/puppeteer"
        "$HOME/.cache/selenium"
        "$HOME/Library/Caches/ms-playwright"
    )
    
    local total_size=0
    
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            local size_kb=$(du -sk "$dir" 2>/dev/null | cut -f1)
            echo -e "  $(basename "$dir"): $(format_size $size_kb)"
            total_size=$((total_size + size_kb))
        fi
    done
    
    echo ""
    echo -e "  ${YELLOW}Łącznie: $(format_size $total_size)${NC}"
    echo ""
    
    if confirm_action "Usunąć wszystkie przeglądarki testowe?"; then
        for dir in "${dirs[@]}"; do
            if [ -d "$dir" ]; then
                rm -rf "$dir"
            fi
        done
        echo -e "${GREEN}✓ Usunięto!${NC}"
    fi
    
    read -p "Naciśnij Enter aby kontynuować..."
}

# Opróżnianie kosza
empty_trash() {
    show_header
    echo -e "${WHITE}🗑️  KOSZ${NC}"
    echo ""
    
    local trash_dir="$HOME/.Trash"
    
    if [ -d "$trash_dir" ]; then
        local size_kb=$(du -sk "$trash_dir" 2>/dev/null | cut -f1)
        local count=$(find "$trash_dir" -type f 2>/dev/null | wc -l | tr -d ' ')
        
        echo -e "Rozmiar kosza: $(format_size $size_kb)"
        echo -e "Liczba plików: $count"
        echo ""
        
        if [ "$size_kb" -gt 0 ]; then
            if confirm_action "Opróżnić kosz?"; then
                rm -rf "$trash_dir"/*
                echo -e "${GREEN}✓ Kosz opróżniony!${NC}"
            fi
        else
            echo -e "${GRAY}Kosz jest pusty.${NC}"
        fi
    fi
    
    read -p "Naciśnij Enter aby kontynuować..."
}

# Przeglądanie Downloads
browse_downloads() {
    show_header
    echo -e "${WHITE}📥 DOWNLOADS - STARE PLIKI${NC}"
    echo ""
    
    local downloads_dir="$HOME/Downloads"
    
    echo -e "Pliki starsze niż ${OLD_FILE_DAYS} dni:"
    echo ""
    
    local files=()
    local idx=1
    
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local file=$(echo "$line" | awk -F'\t' '{print $2}')
            local size_kb=$(du -sk "$file" 2>/dev/null | cut -f1)
            local age=$(( ($(date +%s) - $(stat -f "%m" "$file" 2>/dev/null || echo 0)) / 86400 ))
            local name=$(basename "$file")
            
            echo -e "  ${CYAN}$idx)${NC} $name ${GRAY}($(format_size $size_kb), $age dni)${NC}"
            files+=("$file")
            idx=$((idx + 1))
            
            if [ $idx -gt 20 ]; then
                break
            fi
        fi
    done < <(find "$downloads_dir" -maxdepth 1 -type f -mtime +${OLD_FILE_DAYS} -exec stat -f "%m%t%N" {} \; 2>/dev/null | sort -n)
    
    if [ ${#files[@]} -eq 0 ]; then
        echo -e "${GRAY}Brak starych plików.${NC}"
        read -p "Naciśnij Enter aby kontynuować..."
        return
    fi
    
    echo ""
    echo -e "  ${CYAN}d)${NC} Usuń wybrane (podaj numery oddzielone spacją)"
    echo -e "  ${CYAN}b)${NC} Backup wszystkich do dysku zewnętrznego"
    echo -e "  ${CYAN}0)${NC} Powrót"
    echo ""
    read -p "Wybierz opcję: " choice
    
    case $choice in
        0) return ;;
        b|B)
            backup_files_to_external "${files[@]}"
            ;;
        d|D)
            read -p "Podaj numery plików do usunięcia (np. 1 3 5): " nums
            for num in $nums; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#files[@]}" ]; then
                    local file="${files[$((num-1))]}"
                    echo -e "${GRAY}Usuwanie: $(basename "$file")${NC}"
                    rm -f "$file"
                fi
            done
            echo -e "${GREEN}✓ Usunięto!${NC}"
            ;;
    esac
    
    read -p "Naciśnij Enter aby kontynuować..."
}

# Czyszczenie Cursor cache
clean_cursor_cache() {
    show_header
    echo -e "${WHITE}🔧 CURSOR CACHE${NC}"
    echo ""
    
    local cursor_dirs=(
        "$HOME/.cursor-profiles/*/logs"
        "$HOME/.cursor-profiles/*/CachedData"
        "$HOME/.cursor-profiles/*/GPUCache"
        "$HOME/.cursor/logs"
    )
    
    local total_size=0
    
    for pattern in "${cursor_dirs[@]}"; do
        for dir in $pattern; do
            if [ -d "$dir" ]; then
                local size_kb=$(du -sk "$dir" 2>/dev/null | cut -f1)
                echo -e "  $(echo "$dir" | sed "s|$HOME|~|"): $(format_size $size_kb)"
                total_size=$((total_size + size_kb))
            fi
        done
    done
    
    echo ""
    echo -e "  ${YELLOW}Łącznie: $(format_size $total_size)${NC}"
    echo ""
    
    if confirm_action "Wyczyścić cache Cursor?"; then
        for pattern in "${cursor_dirs[@]}"; do
            for dir in $pattern; do
                if [ -d "$dir" ]; then
                    rm -rf "$dir"
                fi
            done
        done
        echo -e "${GREEN}✓ Cache Cursor wyczyszczony!${NC}"
    fi
    
    read -p "Naciśnij Enter aby kontynuować..."
}

# ============================================================
# SZYBKIE CZYSZCZENIE
# ============================================================

quick_cleanup() {
    show_header
    echo -e "${WHITE}⚡ SZYBKIE CZYSZCZENIE (BEZPIECZNE)${NC}"
    echo ""
    
    local safe_dirs=(
        "$HOME/Library/Caches"
        "$HOME/Library/Logs"
        "$HOME/.npm/_npx"
        "$HOME/.cache/puppeteer"
        "$HOME/.cache/selenium"
    )
    
    local total_size=0
    
    echo -e "Zostaną wyczyszczone:"
    echo ""
    
    for dir in "${safe_dirs[@]}"; do
        if [ -d "$dir" ]; then
            local size_kb=$(du -sk "$dir" 2>/dev/null | cut -f1)
            echo -e "  ✓ $(echo "$dir" | sed "s|$HOME|~|") ${GRAY}($(format_size $size_kb))${NC}"
            total_size=$((total_size + size_kb))
        fi
    done
    
    echo ""
    echo -e "  ${YELLOW}Łącznie do zwolnienia: $(format_size $total_size)${NC}"
    echo ""
    
    if confirm_action "Wykonać szybkie czyszczenie?"; then
        for dir in "${safe_dirs[@]}"; do
            if [ -d "$dir" ]; then
                echo -e "${GRAY}Czyszczenie: $dir${NC}"
                rm -rf "$dir"/* 2>/dev/null || rm -rf "$dir" 2>/dev/null
            fi
        done
        
        # npm cache
        npm cache clean --force 2>/dev/null
        
        echo ""
        echo -e "${GREEN}✓ Czyszczenie zakończone!${NC}"
        echo -e "${GREEN}  Zwolniono około $(format_size $total_size)${NC}"
    fi
    
    read -p "Naciśnij Enter aby kontynuować..."
}

# ============================================================
# BACKUP
# ============================================================

backup_menu() {
    while true; do
        show_header
        show_drive_status
        
        echo -e "${WHITE}💾 BACKUP${NC}"
        echo -e "${GRAY}─────────────────────────────────────────${NC}"
        echo ""
        echo -e "  ${CYAN}1)${NC} 📥 Backup Downloads"
        echo -e "  ${CYAN}2)${NC} 🖥️  Backup Desktop"
        echo -e "  ${CYAN}3)${NC} 📄 Backup Documents"
        echo -e "  ${CYAN}4)${NC} 🎵 Backup Music"
        echo -e "  ${CYAN}5)${NC} 🎬 Backup Movies"
        echo -e "  ${CYAN}6)${NC} 📁 Backup wybranego folderu"
        echo -e "  ${CYAN}7)${NC} ⚡ Pełny backup (wszystkie powyższe)"
        echo -e "  ${CYAN}0)${NC} ← Powrót"
        echo ""
        read -p "Wybierz opcję [0-7]: " choice
        
        case $choice in
            1) backup_folder "$HOME/Downloads" "Downloads" ;;
            2) backup_folder "$HOME/Desktop" "Desktop" ;;
            3) backup_folder "$HOME/Documents" "Documents" ;;
            4) backup_folder "$HOME/Music" "Music" ;;
            5) backup_folder "$HOME/Movies" "Movies" ;;
            6) backup_custom_folder ;;
            7) full_backup ;;
            0) return ;;
        esac
    done
}

# Sprawdzenie dysku zewnętrznego
check_external_drive() {
    if [ ! -d "$EXTERNAL_DRIVE" ]; then
        echo -e "${RED}✗ Dysk zewnętrzny niedostępny: $EXTERNAL_DRIVE${NC}"
        echo -e "${YELLOW}  Podłącz dysk lub zmień ścieżkę w ustawieniach.${NC}"
        read -p "Naciśnij Enter aby kontynuować..."
        return 1
    fi
    return 0
}

# Backup folderu
backup_folder() {
    local source="$1"
    local name="$2"
    
    show_header
    
    if ! check_external_drive; then
        return
    fi
    
    if [ ! -d "$source" ]; then
        echo -e "${RED}Folder źródłowy nie istnieje: $source${NC}"
        read -p "Naciśnij Enter aby kontynuować..."
        return
    fi
    
    local backup_path="$EXTERNAL_DRIVE/$BACKUP_FOLDER/$name"
    local timestamp=$(date +%Y-%m-%d_%H-%M-%S)
    
    local size_kb=$(du -sk "$source" 2>/dev/null | cut -f1)
    
    echo -e "${WHITE}💾 BACKUP: $name${NC}"
    echo ""
    echo -e "Źródło: $source"
    echo -e "Cel: $backup_path"
    echo -e "Rozmiar: $(format_size $size_kb)"
    echo ""
    
    if confirm_action "Wykonać backup?"; then
        mkdir -p "$backup_path"
        
        echo -e "${BLUE}Kopiowanie...${NC}"
        
        # Użyj rsync dla lepszej wydajności
        if command -v rsync &> /dev/null; then
            rsync -avh --progress "$source/" "$backup_path/" 2>&1 | tail -5
        else
            cp -R "$source/"* "$backup_path/" 2>/dev/null
        fi
        
        echo ""
        echo -e "${GREEN}✓ Backup zakończony!${NC}"
        echo -e "  Zapisano do: $backup_path"
    fi
    
    read -p "Naciśnij Enter aby kontynuować..."
}

# Backup wybranego folderu
backup_custom_folder() {
    show_header
    
    if ! check_external_drive; then
        return
    fi
    
    echo -e "${WHITE}📁 BACKUP WYBRANEGO FOLDERU${NC}"
    echo ""
    read -p "Podaj ścieżkę folderu: " source
    
    # Rozwiń tyldę
    source="${source/#\~/$HOME}"
    
    if [ ! -d "$source" ]; then
        echo -e "${RED}Folder nie istnieje: $source${NC}"
        read -p "Naciśnij Enter aby kontynuować..."
        return
    fi
    
    local name=$(basename "$source")
    backup_folder "$source" "$name"
}

# Pełny backup
full_backup() {
    show_header
    
    if ! check_external_drive; then
        return
    fi
    
    echo -e "${WHITE}⚡ PEŁNY BACKUP${NC}"
    echo ""
    
    local folders=(
        "$HOME/Downloads"
        "$HOME/Desktop"
        "$HOME/Documents"
        "$HOME/Music"
        "$HOME/Movies"
    )
    
    local total_size=0
    
    for folder in "${folders[@]}"; do
        if [ -d "$folder" ]; then
            local size_kb=$(du -sk "$folder" 2>/dev/null | cut -f1)
            echo -e "  $(basename "$folder"): $(format_size $size_kb)"
            total_size=$((total_size + size_kb))
        fi
    done
    
    echo ""
    echo -e "  ${YELLOW}Łącznie: $(format_size $total_size)${NC}"
    echo ""
    
    if confirm_action "Wykonać pełny backup?"; then
        for folder in "${folders[@]}"; do
            if [ -d "$folder" ]; then
                local name=$(basename "$folder")
                local backup_path="$EXTERNAL_DRIVE/$BACKUP_FOLDER/$name"
                
                echo -e "${BLUE}Backup: $name...${NC}"
                mkdir -p "$backup_path"
                
                if command -v rsync &> /dev/null; then
                    rsync -ah "$folder/" "$backup_path/" 2>/dev/null
                else
                    cp -R "$folder/"* "$backup_path/" 2>/dev/null
                fi
            fi
        done
        
        echo ""
        echo -e "${GREEN}✓ Pełny backup zakończony!${NC}"
    fi
    
    read -p "Naciśnij Enter aby kontynuować..."
}

# Backup plików do dysku zewnętrznego
backup_files_to_external() {
    local files=("$@")
    
    if ! check_external_drive; then
        return
    fi
    
    local backup_path="$EXTERNAL_DRIVE/$BACKUP_FOLDER/Downloads_Backup_$(date +%Y-%m-%d)"
    mkdir -p "$backup_path"
    
    echo -e "${BLUE}Kopiowanie plików...${NC}"
    
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            cp "$file" "$backup_path/"
            echo -e "  ✓ $(basename "$file")"
        fi
    done
    
    echo ""
    echo -e "${GREEN}✓ Pliki skopiowane do: $backup_path${NC}"
}

# ============================================================
# SYNC
# ============================================================

sync_menu() {
    while true; do
        show_header
        show_drive_status
        
        echo -e "${WHITE}🔄 SYNCHRONIZACJA${NC}"
        echo -e "${GRAY}─────────────────────────────────────────${NC}"
        echo ""
        echo -e "  ${CYAN}1)${NC} ➡️  Sync lokalny → dysk zewnętrzny"
        echo -e "  ${CYAN}2)${NC} ⬅️  Sync dysk zewnętrzny → lokalny"
        echo -e "  ${CYAN}3)${NC} ↔️  Sync dwukierunkowy"
        echo -e "  ${CYAN}4)${NC} 📊 Porównaj różnice"
        echo -e "  ${CYAN}0)${NC} ← Powrót"
        echo ""
        read -p "Wybierz opcję [0-4]: " choice
        
        case $choice in
            1) sync_to_external ;;
            2) sync_from_external ;;
            3) sync_bidirectional ;;
            4) compare_folders ;;
            0) return ;;
        esac
    done
}

# Sync do zewnętrznego
sync_to_external() {
    show_header
    
    if ! check_external_drive; then
        return
    fi
    
    echo -e "${WHITE}➡️  SYNC LOKALNY → DYSK ZEWNĘTRZNY${NC}"
    echo ""
    
    read -p "Podaj folder lokalny (np. ~/Documents): " local_folder
    local_folder="${local_folder/#\~/$HOME}"
    
    if [ ! -d "$local_folder" ]; then
        echo -e "${RED}Folder nie istnieje.${NC}"
        read -p "Naciśnij Enter..."
        return
    fi
    
    local name=$(basename "$local_folder")
    local external_folder="$EXTERNAL_DRIVE/$BACKUP_FOLDER/$name"
    
    echo ""
    echo -e "Źródło: $local_folder"
    echo -e "Cel: $external_folder"
    echo ""
    
    if confirm_action "Rozpocząć synchronizację?"; then
        mkdir -p "$external_folder"
        
        if command -v rsync &> /dev/null; then
            rsync -avh --progress --delete "$local_folder/" "$external_folder/"
        else
            echo -e "${YELLOW}rsync niedostępny, używam cp${NC}"
            cp -R "$local_folder/"* "$external_folder/"
        fi
        
        echo ""
        echo -e "${GREEN}✓ Synchronizacja zakończona!${NC}"
    fi
    
    read -p "Naciśnij Enter..."
}

# Sync z zewnętrznego
sync_from_external() {
    show_header
    
    if ! check_external_drive; then
        return
    fi
    
    echo -e "${WHITE}⬅️  SYNC DYSK ZEWNĘTRZNY → LOKALNY${NC}"
    echo ""
    
    local backup_base="$EXTERNAL_DRIVE/$BACKUP_FOLDER"
    
    if [ ! -d "$backup_base" ]; then
        echo -e "${RED}Brak foldera backupów na dysku zewnętrznym.${NC}"
        read -p "Naciśnij Enter..."
        return
    fi
    
    echo "Dostępne backupy:"
    ls -1 "$backup_base" 2>/dev/null | head -20
    echo ""
    
    read -p "Podaj nazwę folderu do przywrócenia: " folder_name
    read -p "Podaj folder docelowy (np. ~/Restored): " local_folder
    local_folder="${local_folder/#\~/$HOME}"
    
    local external_folder="$backup_base/$folder_name"
    
    if [ ! -d "$external_folder" ]; then
        echo -e "${RED}Folder nie istnieje na dysku zewnętrznym.${NC}"
        read -p "Naciśnij Enter..."
        return
    fi
    
    if confirm_action "Przywrócić $folder_name do $local_folder?"; then
        mkdir -p "$local_folder"
        
        if command -v rsync &> /dev/null; then
            rsync -avh --progress "$external_folder/" "$local_folder/"
        else
            cp -R "$external_folder/"* "$local_folder/"
        fi
        
        echo ""
        echo -e "${GREEN}✓ Przywracanie zakończone!${NC}"
    fi
    
    read -p "Naciśnij Enter..."
}

# Sync dwukierunkowy
sync_bidirectional() {
    show_header
    echo -e "${YELLOW}⚠️  Sync dwukierunkowy wymaga narzędzia unison.${NC}"
    echo ""
    
    if ! command -v unison &> /dev/null; then
        echo -e "Zainstaluj: ${CYAN}brew install unison${NC}"
    else
        echo "unison jest zainstalowany."
        # TODO: Implementacja unison sync
    fi
    
    read -p "Naciśnij Enter..."
}

# Porównanie folderów
compare_folders() {
    show_header
    
    if ! check_external_drive; then
        return
    fi
    
    echo -e "${WHITE}📊 PORÓWNANIE FOLDERÓW${NC}"
    echo ""
    
    read -p "Podaj folder lokalny: " local_folder
    local_folder="${local_folder/#\~/$HOME}"
    
    local name=$(basename "$local_folder")
    local external_folder="$EXTERNAL_DRIVE/$BACKUP_FOLDER/$name"
    
    if [ ! -d "$local_folder" ]; then
        echo -e "${RED}Folder lokalny nie istnieje.${NC}"
        read -p "Naciśnij Enter..."
        return
    fi
    
    if [ ! -d "$external_folder" ]; then
        echo -e "${RED}Folder na dysku zewnętrznym nie istnieje.${NC}"
        read -p "Naciśnij Enter..."
        return
    fi
    
    echo ""
    echo -e "${BLUE}Porównywanie...${NC}"
    echo ""
    
    local local_count=$(find "$local_folder" -type f 2>/dev/null | wc -l | tr -d ' ')
    local external_count=$(find "$external_folder" -type f 2>/dev/null | wc -l | tr -d ' ')
    local local_size=$(du -sh "$local_folder" 2>/dev/null | cut -f1)
    local external_size=$(du -sh "$external_folder" 2>/dev/null | cut -f1)
    
    echo -e "Lokalny:   $local_count plików, $local_size"
    echo -e "Zewnętrzny: $external_count plików, $external_size"
    echo ""
    
    if command -v diff &> /dev/null; then
        echo -e "${GRAY}Różnice (tylko nazwy plików):${NC}"
        diff <(cd "$local_folder" && find . -type f | sort) \
             <(cd "$external_folder" && find . -type f | sort) | head -20
    fi
    
    read -p "Naciśnij Enter..."
}

# ============================================================
# USTAWIENIA
# ============================================================

settings_menu() {
    while true; do
        show_header
        echo -e "${WHITE}⚙️  USTAWIENIA${NC}"
        echo -e "${GRAY}─────────────────────────────────────────${NC}"
        echo ""
        echo -e "  Aktualna konfiguracja:"
        echo -e "  ${GRAY}─────────────────────────────────────────${NC}"
        echo -e "  Dysk zewnętrzny:       ${CYAN}$EXTERNAL_DRIVE${NC}"
        echo -e "  Folder backupów:       ${CYAN}$BACKUP_FOLDER${NC}"
        echo -e "  Pliki starsze niż:     ${CYAN}$OLD_FILE_DAYS dni${NC}"
        echo -e "  Nieużywane od:         ${CYAN}$UNUSED_FILE_DAYS dni${NC}"
        echo -e "  Duże pliki:            ${CYAN}$LARGE_FILE_SIZE_MB MB${NC}"
        echo -e "  Min. rozmiar folderu:  ${CYAN}$MIN_FOLDER_SIZE_MB MB${NC}"
        echo -e "  Tryb szybki:           ${CYAN}$QUICK_MODE${NC}"
        echo -e "  Eksport CSV:           ${CYAN}$EXPORT_CSV${NC}"
        echo -e "  Auto-potwierdzanie:    ${CYAN}$AUTO_CONFIRM${NC}"
        echo ""
        echo -e "  ${CYAN}1)${NC} Zmień ścieżkę dysku zewnętrznego"
        echo -e "  ${CYAN}2)${NC} Zmień folder backupów"
        echo -e "  ${CYAN}3)${NC} Zmień parametry analizy"
        echo -e "  ${CYAN}4)${NC} Przełącz tryb szybki"
        echo -e "  ${CYAN}5)${NC} Przełącz eksport CSV"
        echo -e "  ${CYAN}6)${NC} Przełącz auto-potwierdzanie"
        echo -e "  ${CYAN}7)${NC} Zapisz konfigurację"
        echo -e "  ${CYAN}8)${NC} Otwórz plik konfiguracji"
        echo -e "  ${CYAN}0)${NC} ← Powrót"
        echo ""
        read -p "Wybierz opcję [0-8]: " choice
        
        case $choice in
            1)
                read -p "Nowa ścieżka dysku zewnętrznego: " EXTERNAL_DRIVE
                ;;
            2)
                read -p "Nowy folder backupów: " BACKUP_FOLDER
                ;;
            3)
                read -p "Pliki starsze niż (dni) [$OLD_FILE_DAYS]: " val
                [ -n "$val" ] && OLD_FILE_DAYS="$val"
                read -p "Nieużywane od (dni) [$UNUSED_FILE_DAYS]: " val
                [ -n "$val" ] && UNUSED_FILE_DAYS="$val"
                read -p "Duże pliki (MB) [$LARGE_FILE_SIZE_MB]: " val
                [ -n "$val" ] && LARGE_FILE_SIZE_MB="$val"
                read -p "Min. rozmiar folderu (MB) [$MIN_FOLDER_SIZE_MB]: " val
                [ -n "$val" ] && MIN_FOLDER_SIZE_MB="$val"
                ;;
            4)
                [ "$QUICK_MODE" = true ] && QUICK_MODE=false || QUICK_MODE=true
                ;;
            5)
                [ "$EXPORT_CSV" = true ] && EXPORT_CSV=false || EXPORT_CSV=true
                ;;
            6)
                [ "$AUTO_CONFIRM" = true ] && AUTO_CONFIRM=false || AUTO_CONFIRM=true
                ;;
            7)
                save_config
                read -p "Naciśnij Enter..."
                ;;
            8)
                if command -v open &> /dev/null; then
                    open -e "$CONFIG_FILE"
                else
                    ${EDITOR:-nano} "$CONFIG_FILE"
                fi
                ;;
            0) return ;;
        esac
    done
}

# ============================================================
# POMOC
# ============================================================

show_help() {
    show_header
    echo -e "${WHITE}❓ POMOC${NC}"
    echo -e "${GRAY}─────────────────────────────────────────${NC}"
    echo ""
    echo -e "${CYAN}JUNK MANAGER${NC} - Narzędzie do zarządzania plikami"
    echo ""
    echo -e "${WHITE}FUNKCJE:${NC}"
    echo -e "  • Analiza dysku - identyfikacja niepotrzebnych plików"
    echo -e "  • Interaktywne usuwanie - bezpieczne czyszczenie cache"
    echo -e "  • Backup - kopiowanie do dysku zewnętrznego"
    echo -e "  • Sync - synchronizacja folderów"
    echo ""
    echo -e "${WHITE}BEZPIECZNE DO USUNIĘCIA:${NC}"
    echo -e "  • ~/Library/Caches - cache aplikacji"
    echo -e "  • ~/Library/Logs - logi aplikacji"
    echo -e "  • ~/.npm/_npx - cache npx"
    echo -e "  • ~/.cache/puppeteer - przeglądarki testowe"
    echo ""
    echo -e "${WHITE}WYMAGAJĄ UWAGI:${NC}"
    echo -e "  • ~/Library/Application Support - dane aplikacji"
    echo -e "  • ~/Downloads - sprawdź przed usunięciem"
    echo ""
    echo -e "${WHITE}KONFIGURACJA:${NC}"
    echo -e "  Plik: $CONFIG_FILE"
    echo ""
    
    read -p "Naciśnij Enter..."
}

# ============================================================
# GŁÓWNA PĘTLA
# ============================================================

main() {
    # Wczytaj konfigurację
    load_config
    
    # Sprawdź zależności
    if ! command -v bc &> /dev/null; then
        echo "Błąd: Program 'bc' nie jest zainstalowany."
        echo "Zainstaluj: brew install bc"
        exit 1
    fi
    
    # Główna pętla
    while true; do
        show_main_menu
    done
}

# Uruchom
main "$@"

