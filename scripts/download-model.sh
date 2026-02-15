#!/bin/bash
# Pre-download WhisperKit CoreML model from HuggingFace.
# Usage: ./scripts/download-model.sh [model]
# Models: tiny.en (75MB), base.en (150MB), small.en (500MB), medium.en (1.5GB)
# Default: base.en

set -euo pipefail

MODEL="${1:-base.en}"
VARIANT="openai_whisper-${MODEL}"
REPO="argmaxinc/whisperkit-coreml"
HF_API="https://huggingface.co/api/models/${REPO}"
HF_BASE="https://huggingface.co/${REPO}/resolve/main"

# WhisperKit's Hub library stores models in ~/Documents/huggingface/models/
DEST_DIR="$HOME/Documents/huggingface/models/${REPO}/${VARIANT}"

echo "=== EchoNotes Model Downloader ==="
echo "Model:   ${VARIANT}"
echo "Dest:    ${DEST_DIR}"
echo ""

# Check if already downloaded
if [ -d "$DEST_DIR" ] && [ -f "$DEST_DIR/config.json" ]; then
    FILE_COUNT=$(find "$DEST_DIR" -name "*.mlmodelc" -type d | wc -l | tr -d ' ')
    if [ "$FILE_COUNT" -ge 3 ]; then
        SIZE=$(du -sh "$DEST_DIR" | cut -f1)
        echo "✅ Model already downloaded (${SIZE})"
        echo "   ${DEST_DIR}"
        exit 0
    fi
    echo "⚠ Partial download detected, re-downloading..."
fi

# Get file list from HuggingFace API
echo "Fetching file list..."
FILES=$(curl -sL "${HF_API}/tree/main/${VARIANT}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for f in data:
    if f.get('type') == 'file':
        print(f['path'])
" 2>/dev/null)

if [ -z "$FILES" ]; then
    echo "Error: Could not fetch file list from HuggingFace."
    echo "Try: pip3 install huggingface_hub && huggingface-cli download ${REPO} --include '${VARIANT}/*'"
    exit 1
fi

FILE_COUNT=$(echo "$FILES" | wc -l | tr -d ' ')
echo "Downloading ${FILE_COUNT} files..."
echo ""

mkdir -p "$DEST_DIR"
DOWNLOADED=0

while IFS= read -r filepath; do
    # filepath is like "openai_whisper-base.en/AudioEncoder.mlmodelc/model.mlmodel"
    relative="${filepath#${VARIANT}/}"
    dest_file="${DEST_DIR}/${relative}"
    mkdir -p "$(dirname "$dest_file")"
    
    DOWNLOADED=$((DOWNLOADED + 1))
    printf "[%d/%d] %s... " "$DOWNLOADED" "$FILE_COUNT" "$relative"
    
    if [ -f "$dest_file" ]; then
        echo "exists"
        continue
    fi
    
    HTTP_CODE=$(curl -sL -w "%{http_code}" -o "$dest_file" "${HF_BASE}/${filepath}")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "ok"
    else
        echo "FAILED (HTTP ${HTTP_CODE})"
        rm -f "$dest_file"
    fi
done <<< "$FILES"

echo ""
SIZE=$(du -sh "$DEST_DIR" | cut -f1)
echo "✅ Done! Model downloaded (${SIZE})"
echo "   ${DEST_DIR}"
echo ""
echo "Launch EchoNotes — transcription will work immediately."
