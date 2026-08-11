#!/bin/bash
# recon.sh - Bug Bounty Recon Workflow (MVP)
# Uso: ./recon.sh targets.txt
# Requisitos previos: subfinder, httpx, nuclei, nmap, jq, ffuf (opcionales)

set -euo pipefail
IFS=$'\n\t'

if [ "$#" -ne 1 ]; then
  echo "Uso: $0 targets.txt"
  exit 1
fi

TARGET_FILE="$1"
OUT_ROOT="results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$OUT_ROOT"

echo "[*] Leyendo targets desde $TARGET_FILE"
while read -r TARGET || [ -n "$TARGET" ]; do
  TARGET=$(echo "$TARGET" | xargs) # trim
  [ -z "$TARGET" ] && continue
  echo "---------------------------------------------"
  echo "[*] Iniciando recon para: $TARGET"
  TARGET_DIR="$OUT_ROOT/${TARGET}_${TIMESTAMP}"
  mkdir -p "$TARGET_DIR"

  # 1) Subdomain discovery (subfinder)
  if command -v subfinder >/dev/null 2>&1; then
    echo "[+] Subfinder: descubriendo subdominios..."
    subfinder -d "$TARGET" -silent > "$TARGET_DIR/subdomains.txt"
    echo "Subdominios encontrados: $(wc -l < "$TARGET_DIR/subdomains.txt")"
  else
    echo "[-] subfinder no instalado, omitiendo."
    touch "$TARGET_DIR/subdomains.txt"
  fi

  # 2) HTTP probing (httpx)
  if command -v httpx >/dev/null 2>&1; then
    echo "[+] httpx: filtrando hosts vivos..."
    httpx -l "$TARGET_DIR/subdomains.txt" -silent -o "$TARGET_DIR/http_probe.txt" -title -status-code -tech-detect
    echo "Hosts vivos: $(wc -l < "$TARGET_DIR/http_probe.txt")"
  else
    echo "[-] httpx no instalado, omitiendo."
    cp "$TARGET_DIR/subdomains.txt" "$TARGET_DIR/http_probe.txt"
  fi

  # 3) Escaneo de puertos con Nmap
  if command -v nmap >/dev/null 2>&1; then
    echo "[+] Nmap: escaneando puertos comunes en hosts vivos..."
    nmap -iL "$TARGET_DIR/http_probe.txt" -T4 -F -oN "$TARGET_DIR/nmap_scan.txt" >/dev/null 2>&1
    echo "Escaneo de puertos completado."
  else
    echo "[-] nmap no instalado, omitiendo."
    touch "$TARGET_DIR/nmap_scan.txt"
  fi

  # 4) Nuclei (detección de vulnerabilidades)
  if command -v nuclei >/dev/null 2>&1; then
    echo "[+] Nuclei: escaneando vulnerabilidades..."
    nuclei -l "$TARGET_DIR/http_probe.txt" -silent -severity low,medium,high,critical -o "$TARGET_DIR/nuclei_results.txt"
    echo "Vulnerabilidades encontradas: $(wc -l < "$TARGET_DIR/nuclei_results.txt")"
  else
    echo "[-] nuclei no instalado, omitiendo."
    touch "$TARGET_DIR/nuclei_results.txt"
  fi

  # 5) Resumen final
  echo "---------------------------------------------"
  echo "[✓] Recon completado para $TARGET"
  echo "Resultados guardados en: $TARGET_DIR"
  echo "---------------------------------------------"
done < "$TARGET_FILE"

echo "[*] Todos los reconocimientos finalizados."
