#!/bin/bash
# Run Claude Status App

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Activate virtual environment
if [ -d "venv" ]; then
    source venv/bin/activate
else
    echo "Virtual environment not found. Running setup first..."
    ./setup.sh
    source venv/bin/activate
fi

# Run the app
python3 claude_status.py
