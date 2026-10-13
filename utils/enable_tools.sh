#!/bin/bash

# Detect if the script is executed directly instead of sourced
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "⚠️  AVISO: Este script deve ser carregado via 'source' (ou '.') para exportar variáveis para sua sessão atual:"
    echo "    source $0"
fi

QUIET_MODE=0
if [ "$1" = "-q" ] || [ "$1" = "--quiet" ] || [ -n "$QUIET" ]; then
    QUIET_MODE=1
fi

# 1. configure DISPLAY for x2go session
RAW_DISPLAY=$(ps eww -u $USER 2>/dev/null | grep -o -m 1 '[D]ISPLAY=nx/nx[^ ]*')

if [ -z "$RAW_DISPLAY" ]; then
    [ $QUIET_MODE -eq 1 ] || echo "No x2go session found."
else
    DISPLAY_NUM=${RAW_DISPLAY##*:}
    export DISPLAY=":$DISPLAY_NUM"
    [ $QUIET_MODE -eq 1 ] || echo "✅ Success! DISPLAY configured to $DISPLAY"
fi

# 2. Start the Synopsys environment
SNPS_SCRIPT="/Tools/synopsys-scripts/snps.sh"
if [ -f "$SNPS_SCRIPT" ]; then
    source "$SNPS_SCRIPT"
    [ $QUIET_MODE -eq 1 ] || echo "✅ Synopsys tools environment loaded successfully."
else
    [ $QUIET_MODE -eq 1 ] || echo "⚠️  $SNPS_SCRIPT not found."
fi