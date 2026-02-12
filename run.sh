#!/bin/sh
# Launch Compiler Explorer with local m68k compilers
# Usage: ./run.sh [dev|run|run-only]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CE_DIR="$SCRIPT_DIR/compiler-explorer"
export NODE_DIR="/opt/node"
export PATH="$NODE_DIR/bin:$PATH"

cd "$CE_DIR" || exit 1

MODE="${1:-run-only}"

case "$MODE" in
    dev)
        echo "Starting Compiler Explorer in dev mode (C + C++)..."
        make dev EXTRA_ARGS='--language c --language c++'
        ;;
    run)
        echo "Building and starting Compiler Explorer (C + C++)..."
        make run EXTRA_ARGS='--language c --language c++'
        ;;
    run-only)
        echo "Starting Compiler Explorer in production mode (C + C++)..."
        make run-only EXTRA_ARGS='--language c --language c++'
        ;;
    *)
        echo "Usage: $0 [dev|run|run-only]"
        exit 1
        ;;
esac
