#!/bin/bash

# Uruchamia wszystkie testy i generuje raport

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║${NC}         ${BOLD}SUITE TESTÓW - JUNK MANAGER${NC}                ${BOLD}║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Uruchom testy jednostkowe
echo -e "${BLUE}📦 Uruchamianie testów jednostkowych...${NC}"
echo ""
bash "$SCRIPT_DIR/test_runner.sh"
UNIT_RESULT=$?

echo ""
echo -e "${BLUE}─────────────────────────────────────────${NC}"
echo ""

# Uruchom testy integracyjne
echo -e "${BLUE}🔗 Uruchamianie testów integracyjnych...${NC}"
echo ""
bash "$SCRIPT_DIR/test_integration.sh"
INTEGRATION_RESULT=$?

# Podsumowanie końcowe
echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║${NC}              ${BOLD}RAPORT KOŃCOWY${NC}                      ${BOLD}║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ $UNIT_RESULT -eq 0 ]; then
    echo -e "  ${GREEN}✓ Testy jednostkowe:${NC} ${GREEN}PRZESZŁY${NC}"
else
    echo -e "  ${RED}✗ Testy jednostkowe:${NC} ${RED}NIE PRZESZŁY${NC}"
fi

if [ $INTEGRATION_RESULT -eq 0 ]; then
    echo -e "  ${GREEN}✓ Testy integracyjne:${NC} ${GREEN}PRZESZŁY${NC}"
else
    echo -e "  ${RED}✗ Testy integracyjne:${NC} ${RED}NIE PRZESZŁY${NC}"
fi

echo ""

if [ $UNIT_RESULT -eq 0 ] && [ $INTEGRATION_RESULT -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ Wszystkie testy przeszły pomyślnie!${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}✗ Niektóre testy nie przeszły${NC}"
    exit 1
fi

