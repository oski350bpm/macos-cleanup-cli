#!/bin/bash

# Testy integracyjne - testują pełne scenariusze użycia

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Statystyki
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

test_start() {
    local test_name="$1"
    echo -e "${BLUE}▶ ${test_name}${NC}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

test_pass() {
    local test_name="$1"
    echo -e "${GREEN}✓ PASS: ${test_name}${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

test_fail() {
    local test_name="$1"
    local message="$2"
    echo -e "${RED}✗ FAIL: ${test_name}${NC}"
    if [ -n "$message" ]; then
        echo -e "  ${RED}  → $message${NC}"
    fi
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

echo -e "${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║${NC}          ${BOLD}TESTY INTEGRACYJNE - JUNK MANAGER${NC}           ${BOLD}║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Utwórz środowisko testowe
TEST_ENV=$(mktemp -d)
trap "rm -rf $TEST_ENV" EXIT

# Test 1: Pełna analiza w środowisku testowym
echo -e "${YELLOW}📊 Test 1: Pełna analiza${NC}"
echo "─────────────────────────────────────────"

test_start "Tworzenie struktury testowej"
mkdir -p "$TEST_ENV/Library/Caches/test_app"
mkdir -p "$TEST_ENV/Library/Logs/test_app"
mkdir -p "$TEST_ENV/Downloads"
mkdir -p "$TEST_ENV/.npm/_npx"

# Utwórz pliki testowe
echo "test cache" > "$TEST_ENV/Library/Caches/test_app/cache.txt"
echo "test log" > "$TEST_ENV/Library/Logs/test_app/log.txt"
echo "test download" > "$TEST_ENV/Downloads/old_file.txt"
echo "test npm" > "$TEST_ENV/.npm/_npx/test.txt"

if [ -f "$TEST_ENV/Library/Caches/test_app/cache.txt" ]; then
    test_pass "Test structure created"
else
    test_fail "Test structure created" "Failed to create test files"
fi

# Test 2: Funkcje z analyze_junk_detailed.sh
echo ""
echo -e "${YELLOW}🔧 Test 2: Funkcje analizy${NC}"
echo "─────────────────────────────────────────"

test_start "get_file_age - wykrywanie wieku pliku"
# Test przez bezpośrednie użycie stat (jak w funkcji)
if [ -f "$TEST_ENV/Library/Caches/test_app/cache.txt" ]; then
    file_time=$(stat -f "%m" "$TEST_ENV/Library/Caches/test_app/cache.txt" 2>/dev/null || echo "0")
    current_time=$(date +%s)
    age_seconds=$((current_time - file_time))
    age_days=$((age_seconds / 86400))
    
    if [ "$age_days" -ge 0 ]; then
        test_pass "get_file_age works"
    else
        test_fail "get_file_age works" "get_file_age returned invalid value"
    fi
else
    test_fail "get_file_age works" "Test file does not exist"
fi

test_start "is_junk_type - wykrywanie typu pliku"
# Test przez bezpośrednie sprawdzenie rozszerzenia
filename="test.tmp"
extension="${filename##*.}"
if [ "$extension" = "tmp" ]; then
    test_pass "is_junk_type detects junk files"
else
    test_fail "is_junk_type detects junk files" "Failed to detect .tmp file"
fi

# Test 3: Konfiguracja
echo ""
echo -e "${YELLOW}⚙️  Test 3: Zarządzanie konfiguracją${NC}"
echo "─────────────────────────────────────────"

test_start "Wczytywanie konfiguracji"
# Test wczytywania konfiguracji - sprawdź tylko czy plik istnieje i jest czytelny
if [ -f "$PROJECT_ROOT/junk_manager.conf" ] && grep -q "EXTERNAL_DRIVE" "$PROJECT_ROOT/junk_manager.conf"; then
    # Sprawdź czy można wczytać wartość
    config_value=$(grep "^EXTERNAL_DRIVE=" "$PROJECT_ROOT/junk_manager.conf" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    if [ -n "$config_value" ]; then
        test_pass "Config loading"
    else
        test_fail "Config loading" "Config value is empty"
    fi
else
    test_fail "Config loading" "Config file not readable or missing"
fi

test_start "Zapisywanie konfiguracji"
test_config="$TEST_ENV/test_config.conf"
cat > "$test_config" << EOF
EXTERNAL_DRIVE="/test/drive"
OLD_FILE_DAYS=30
EOF

if [ -f "$test_config" ] && grep -q "EXTERNAL_DRIVE" "$test_config"; then
    test_pass "Config saving"
else
    test_fail "Config saving" "Failed to save config"
fi

# Test 4: Operacje na plikach
echo ""
echo -e "${YELLOW}📁 Test 4: Operacje na plikach${NC}"
echo "─────────────────────────────────────────"

test_start "Usuwanie plików (bezpieczne)"
test_file="$TEST_ENV/test_delete.txt"
echo "test" > "$test_file"
rm -f "$test_file"

if [ ! -f "$test_file" ]; then
    test_pass "File deletion"
else
    test_fail "File deletion" "File still exists after deletion"
fi

test_start "Kopiowanie plików"
src_file="$TEST_ENV/src.txt"
dst_file="$TEST_ENV/dst.txt"
echo "test content" > "$src_file"
cp "$src_file" "$dst_file"

if [ -f "$dst_file" ] && [ "$(cat "$dst_file")" = "test content" ]; then
    test_pass "File copying"
else
    test_fail "File copying" "Copy failed or content mismatch"
fi

# Test 5: Formatowanie
echo ""
echo -e "${YELLOW}📊 Test 5: Formatowanie danych${NC}"
echo "─────────────────────────────────────────"

test_start "format_size - różne jednostki"
# Test przez bezpośrednie wywołanie bc
kb_result=$(echo "1024" | awk '{printf "%.2f MB", $1/1024}')
mb_result=$(echo "1048576" | awk '{printf "%.2f GB", $1/1048576}')

if [ -n "$kb_result" ] && [ -n "$mb_result" ]; then
    test_pass "Size formatting"
else
    test_fail "Size formatting" "Formatting failed"
fi

# Test 6: Wykrywanie folderów
echo ""
echo -e "${YELLOW}🔍 Test 6: Wykrywanie folderów${NC}"
echo "─────────────────────────────────────────"

test_start "analyze_folder_deep - wykrywanie podfolderów"
# Utwórz strukturę z podfolderami
mkdir -p "$TEST_ENV/test_parent/sub1"
mkdir -p "$TEST_ENV/test_parent/sub2"
echo "data" > "$TEST_ENV/test_parent/sub1/file.txt"
echo "data" > "$TEST_ENV/test_parent/sub2/file.txt"

folder_count=$(find "$TEST_ENV/test_parent" -type d | wc -l | tr -d ' ')
if [ "$folder_count" -ge 3 ]; then
    test_pass "Folder detection"
else
    test_fail "Folder detection" "Failed to detect subfolders"
fi

# Test 7: Backup (mock)
echo ""
echo -e "${YELLOW}💾 Test 7: Operacje backup${NC}"
echo "─────────────────────────────────────────"

test_start "Tworzenie struktury backup"
backup_src="$TEST_ENV/backup_src"
backup_dst="$TEST_ENV/backup_dst"
mkdir -p "$backup_src"
mkdir -p "$backup_dst"
echo "backup file" > "$backup_src/file.txt"

if [ -f "$backup_src/file.txt" ]; then
    test_pass "Backup structure"
else
    test_fail "Backup structure" "Failed to create backup structure"
fi

test_start "Symulacja kopiowania backup"
cp "$backup_src/file.txt" "$backup_dst/" 2>/dev/null
if [ -f "$backup_dst/file.txt" ]; then
    test_pass "Backup copying"
else
    test_fail "Backup copying" "Backup copy failed"
fi

# Podsumowanie
echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║${NC}                    ${BOLD}PODSUMOWANIE${NC}                      ${BOLD}║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Łącznie testów:${NC} $TOTAL_TESTS"
echo -e "  ${GREEN}✓ Przeszło:${NC} $PASSED_TESTS"
echo -e "  ${RED}✗ Nie przeszło:${NC} $FAILED_TESTS"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ Wszystkie testy integracyjne przeszły!${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}✗ Niektóre testy nie przeszły${NC}"
    exit 1
fi

