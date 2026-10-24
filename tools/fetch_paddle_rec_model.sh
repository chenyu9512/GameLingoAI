#!/usr/bin/env bash
# Fetch the official PP-OCRv6 Small recognition ONNX model for the offline build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_DIR="$ROOT/ios/GameLingoAI/PaddleModels/rec"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MODEL="PP-OCRv6_small_rec_onnx_infer"
BASE="https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0"
mkdir -p "$MODEL_DIR"
curl --fail --location --retry 3 --retry-delay 2 \
     --connect-timeout 20 --max-time 600 \
     "$BASE/$MODEL.tar" -o "$TMP/model.tar"
tar -xf "$TMP/model.tar" -C "$TMP"
SOURCE="$TMP/$MODEL"
test -s "$SOURCE/inference.onnx" || { echo "PaddleOCR ONNX model missing"; exit 1; }
test -s "$SOURCE/inference.yml" || { echo "PaddleOCR YAML configuration missing"; exit 1; }
cp "$SOURCE/inference.onnx" "$MODEL_DIR/inference.onnx"
cp "$SOURCE/inference.yml" "$MODEL_DIR/inference.yml"

# Ruby YAML is available on Codemagic, no extra Python packages required.
ruby -ryaml -e '
  source = YAML.load_file(ARGV[0])
  values = source.fetch("PostProcess").fetch("character_dict")
  abort("Empty character dictionary") unless values.is_a?(Array) && values.size > 100
  File.write(ARGV[1], values.map(&:to_s).join("\n") + "\n")
' "$MODEL_DIR/inference.yml" "$MODEL_DIR/characters.txt"
BYTES="$(wc -c < "$MODEL_DIR/inference.onnx" | tr -d ' ')"
test "$BYTES" -gt 1000000 || { echo "Model file is implausibly small"; exit 1; }
echo "PASS PaddleOCR recognition model and $(wc -l < "$MODEL_DIR/characters.txt") characters; ${BYTES} bytes"
