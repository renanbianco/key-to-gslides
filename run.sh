#!/bin/bash
# Launch the Keynote → Google Slides converter app.
cd "$(dirname "$0")"

# Install dependencies if not already installed
python3 -c "import pptx, googleapiclient" 2>/dev/null || {
    echo "Installing dependencies..."
    pip3 install -r requirements.txt -q
}

python3 -W ignore main.py
