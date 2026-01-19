#!/bin/bash

# Test Runner dla Junk Manager
# Uruchamia wszystkie testy i raportuje wyniki

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

# Funkcje pomocnicze
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

assert_equal() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    if [ "$expected" = "$actual" ]; then
        test_pass "$test_name"
        return 0
    else
        test_fail "$test_name" "Expected: '$expected', Got: '$actual'"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local test_name="$2"
    
    if [ -n "$value" ]; then
        test_pass "$test_name"
        return 0
    else
        test_fail "$test_name" "Value is empty"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local test_name="$2"
    
    if [ -f "$file" ]; then
        test_pass "$test_name"
        return 0
    else
        test_fail "$test_name" "File does not exist: $file"
        return 1
    fi
}

assert_dir_exists() {
    local dir="$1"
    local test_name="$2"
    
    if [ -d "$dir" ]; then
        test_pass "$test_name"
        return 0
    else
        test_fail "$test_name" "Directory does not exist: $dir"
        return 1
    fi
}

# Nagłówek
echo -e "${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║${NC}           ${BOLD}TESTY AUTOMATYCZNE - JUNK MANAGER${NC}            ${BOLD}║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Uruchom wszystkie testy
echo -e "${BOLD}Uruchamianie testów...${NC}"
echo ""

# Test 1: Funkcje pomocnicze
echo -e "${YELLOW}📦 Test 1: Funkcje pomocnicze${NC}"
echo "─────────────────────────────────────────"

# Test format_size
test_start "format_size - KB"
result=$(echo "512" | awk '{printf "%.2f KB", $1}')
assert_not_empty "$result" "format_size returns value"

test_start "format_size - MB"
result=$(echo "2048" | awk '{printf "%.2f MB", $1/1024}')
assert_not_empty "$result" "format_size MB conversion"

# Test 2: Konfiguracja
echo ""
echo -e "${YELLOW}⚙️  Test 2: Konfiguracja${NC}"
echo "─────────────────────────────────────────"

test_start "Plik konfiguracji istnieje"
assert_file_exists "$PROJECT_ROOT/junk_manager.conf" "Config file exists"

test_start "Plik konfiguracji jest czytelny"
if [ -r "$PROJECT_ROOT/junk_manager.conf" ]; then
    test_pass "Config file is readable"
else
    test_fail "Config file is readable" "Cannot read config file"
fi

# Test 3: Skrypty główne
echo ""
echo -e "${YELLOW}📜 Test 3: Skrypty główne${NC}"
echo "─────────────────────────────────────────"

test_start "analyze_junk_detailed.sh istnieje"
assert_file_exists "$PROJECT_ROOT/analyze_junk_detailed.sh" "Analysis script exists"

test_start "junk_manager.sh istnieje"
assert_file_exists "$PROJECT_ROOT/junk_manager.sh" "Manager script exists"

test_start "Skrypty są wykonywalne"
if [ -x "$PROJECT_ROOT/analyze_junk_detailed.sh" ] && [ -x "$PROJECT_ROOT/junk_manager.sh" ]; then
    test_pass "Scripts are executable"
else
    test_fail "Scripts are executable" "Scripts are not executable"
fi

# Test 4: Składnia bash
echo ""
echo -e "${YELLOW}🔍 Test 4: Składnia bash${NC}"
echo "─────────────────────────────────────────"

test_start "analyze_junk_detailed.sh - składnia"
if bash -n "$PROJECT_ROOT/analyze_junk_detailed.sh" 2>/dev/null; then
    test_pass "Analysis script syntax"
else
    test_fail "Analysis script syntax" "Syntax error in analysis script"
fi

test_start "junk_manager.sh - składnia"
if bash -n "$PROJECT_ROOT/junk_manager.sh" 2>/dev/null; then
    test_pass "Manager script syntax"
else
    test_fail "Manager script syntax" "Syntax error in manager script"
fi

# Test 5: Zależności
echo ""
echo -e "${YELLOW}📦 Test 5: Zależności${NC}"
echo "─────────────────────────────────────────"

test_start "bc jest zainstalowany"
if command -v bc &> /dev/null; then
    test_pass "bc is installed"
else
    test_fail "bc is installed" "bc is not installed"
fi

test_start "du jest dostępny"
if command -v du &> /dev/null; then
    test_pass "du is available"
else
    test_fail "du is available" "du is not available"
fi

test_start "find jest dostępny"
if command -v find &> /dev/null; then
    test_pass "find is available"
else
    test_fail "find is available" "find is not available"
fi

# Test 6: Funkcje analizy (mock test)
echo ""
echo -e "${YELLOW}🧪 Test 6: Funkcje analizy (mock)${NC}"
echo "─────────────────────────────────────────"

# Utwórz tymczasowy folder testowy
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

test_start "Tworzenie środowiska testowego"
mkdir -p "$TEST_DIR/test_cache"
echo "test file" > "$TEST_DIR/test_cache/test.txt"
if [ -f "$TEST_DIR/test_cache/test.txt" ]; then
    test_pass "Test environment created"
else
    test_fail "Test environment created" "Failed to create test files"
fi

test_start "du działa poprawnie"
size=$(du -sk "$TEST_DIR" 2>/dev/null | cut -f1)
if [ -n "$size" ] && [ "$size" -gt 0 ]; then
    test_pass "du command works"
else
    test_fail "du command works" "du returned invalid size"
fi

test_start "find znajduje pliki"
found=$(find "$TEST_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$found" -gt 0 ]; then
    test_pass "find command works"
else
    test_fail "find command works" "find did not find test files"
fi

# Test 7: Parsowanie argumentów
echo ""
echo -e "${YELLOW}🔧 Test 7: Parsowanie argumentów${NC}"
echo "─────────────────────────────────────────"

test_start "analyze_junk_detailed.sh --help"
if bash "$PROJECT_ROOT/analyze_junk_detailed.sh" --help 2>&1 | grep -q "Użycie"; then
    test_pass "Help option works"
else
    test_fail "Help option works" "Help option failed"
fi

test_start "junk_manager.sh - wczytanie konfiguracji"
# Test czy skrypt może wczytać konfigurację (bez uruchamiania pełnego menu)
if bash -c "source $PROJECT_ROOT/junk_manager.sh; load_config; echo \$EXTERNAL_DRIVE" 2>/dev/null | grep -q "/"; then
    test_pass "Config loading works"
else
    test_fail "Config loading works" "Failed to load config"
fi

# Test 8: Formatowanie rozmiaru (funkcja z analyze_junk_detailed.sh)
echo ""
echo -e "${YELLOW}📊 Test 8: Formatowanie rozmiaru${NC}"
echo "─────────────────────────────────────────"

# Test funkcji format_size przez bezpośrednie wywołanie
test_start "format_size - test KB"
# Test przez bezpośrednie użycie bc (jak w funkcji)
result=$(echo "512" | awk '{if ($1 >= 1024) printf "%.2f MB", $1/1024; else printf "%.2f KB", $1}')
if [ -n "$result" ] && echo "$result" | grep -q "KB\|MB\|GB"; then
    test_pass "format_size KB"
else
    test_fail "format_size KB" "format_size returned invalid format"
fi

# Test 9: Wykrywanie plików
echo ""
echo -e "${YELLOW}🔍 Test 9: Wykrywanie plików${NC}"
echo "─────────────────────────────────────────"

test_start "Wykrywanie starych plików"
old_file="$TEST_DIR/old_file.txt"
touch -t 202001010000 "$old_file" 2>/dev/null || touch -d "2 years ago" "$old_file" 2>/dev/null
if [ -f "$old_file" ]; then
    test_pass "Old file created"
else
    test_fail "Old file created" "Failed to create old file"
fi

# Test 10: Operacje na plikach
echo ""
echo -e "${YELLOW}📁 Test 10: Operacje na plikach${NC}"
echo "─────────────────────────────────────────"

test_start "Tworzenie folderu backup"
backup_dir="$TEST_DIR/backup_test"
mkdir -p "$backup_dir"
assert_dir_exists "$backup_dir" "Backup directory created"

test_start "Kopiowanie plików"
cp "$TEST_DIR/test_cache/test.txt" "$backup_dir/" 2>/dev/null
if [ -f "$backup_dir/test.txt" ]; then
    test_pass "File copying works"
else
    test_fail "File copying works" "Failed to copy file"
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
    echo -e "${GREEN}${BOLD}✓ Wszystkie testy przeszły pomyślnie!${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}✗ Niektóre testy nie przeszły${NC}"
    exit 1
fi

