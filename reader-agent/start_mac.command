#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

if [ -f ".core/reader_agent.py" ]; then
    python3 .core/reader_agent.py
else
    python3 reader_agent.py
fi
