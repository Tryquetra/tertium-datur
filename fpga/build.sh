#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
mkdir -p "${BUILD_DIR}"

YOSYS="${YOSYS:-yosys}"
NEXTPNR="${NEXTPNR:-${HOME}/.local/bin/nextpnr-himbaechel}"
GOWIN_PACK="${GOWIN_PACK:-${HOME}/.local/bin/gowin_pack}"
LOADER="${LOADER:-openFPGALoader}"

echo "[1/3] Synthesizing RTL with yosys..."
"${YOSYS}" -q -p "read_verilog ${SCRIPT_DIR}/td_uart.v ${SCRIPT_DIR}/td_hdmi.v ${SCRIPT_DIR}/tertium_datur_top.v; synth_gowin -top tertium_datur_top -family gw2a -json ${BUILD_DIR}/tertium_datur.json"

echo "[2/3] Place and route with nextpnr-himbaechel..."
"${NEXTPNR}" \
  --json "${BUILD_DIR}/tertium_datur.json" \
  --write "${BUILD_DIR}/tertium_datur_pnr.json" \
  --device "GW2AR-LV18QN88C8/I7" \
  --vopt family=GW2A-18C \
  --vopt cst="${SCRIPT_DIR}/tangnano20k.cst" \
  2>&1 | tee "${BUILD_DIR}/nextpnr.log"

echo "[3/3] Packing bitstream with gowin_pack..."
"${GOWIN_PACK}" -d GW2A-18C -c --mspi_as_gpio -o "${BUILD_DIR}/tertium_datur.fs" "${BUILD_DIR}/tertium_datur_pnr.json"

ls -lh "${BUILD_DIR}/tertium_datur.fs"

if [[ "${1:-}" == "--flash" ]]; then
  echo "[flash] Programming Tang Nano 20K SRAM via openFPGALoader..."
  "${LOADER}" -b tangnano20k "${BUILD_DIR}/tertium_datur.fs"
fi
