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
    echo "[*] subfinder -> $TARGET"
    subfinder -d "$TARGET" -silent -o "$TARGET_DIR/subdomains.txt" || true
  else
    echo "[!] subfinder no encontrado, saltando (instala subfinder para mejor resultado)"
  fi

  # 2) Probe for alive hosts (httpx)
  if command -v httpx >/dev/null 2>&1; then
    echo "[*] httpx -> probando hosts vivos"
    if [ -s "$TARGET_DIR/subdomains.txt" ]; then
      cat "$TARGET_DIR/subdomains.txt" | httpx -silent -json -o "$TARGET_DIR/httpx.json" || true
    else
      echo "[!] No hay subdominios en subdomains.txt — probando domain directo"
      echo "$TARGET" | httpx -silent -json -o "$TARGET_DIR/httpx.json" || true
    fi
  else
    echo "[!] httpx no encontrado, saltando verificación HTTP"
  fi

  # 3) Nuclei scan (quick templates)
  if command -v nuclei >/dev/null 2>&1; then
    echo "[*] nuclei -> escaneo rápido"
    if [ -s "$TARGET_DIR/httpx.json" ]; then
      cat "$TARGET_DIR/httpx.json" | jq -r '.ip? // .url? // .host? // empty' > "$TARGET_DIR/hosts_for_nuclei.txt" || true
      # nuclei espera URLs/hosts por línea
      nuclei -l "$TARGET_DIR/hosts_for_nuclei.txt" -t cves/ -o "$TARGET_DIR/nuclei_results.txt" -silent || true
    else
      nuclei -u "$TARGET" -o "$TARGET_DIR/nuclei_results.txt" -silent || true
    fi
  else
    echo "[!] nuclei no instalado, saltando"
  fi

  # 4) Basic nmap scan for alive HTTP hosts
  if command -v nmap >/dev/null 2>&1 && [ -s "$TARGET_DIR/httpx.json" ]; then
    echo "[*] nmap -> escaneo rápido de puertos en hosts HTTP"
    cat "$TARGET_DIR/httpx.json" | jq -r '.ip? // .url? // .host? // empty' | while read -r HOSTLine; do
      HOST=$(echo "$HOSTLine" | sed -E 's#https?://##; s#/.*##')
      echo "[*] nmap $HOST"
      nmap -sV -Pn -p 1-2000 "$HOST" -oN "$TARGET_DIR/nmap_${HOST}.txt" || true
    done
  else
    echo "[!] nmap no disponible o no hay hosts HTTP detectados"
  fi

  # 5) Optional: ffuf / dir bruteforce (requires wordlist)
  if command -v ffuf >/dev/null 2>&1; then
    WORDLIST="/usr/share/wordlists/dirb/common.txt"
    if [ -f "$WORDLIST" ]; then
      echo "[*] ffuf -> dir bruteforce (primer host HTTPS/HTTP)"
      FIRST_URL=$(jq -r '.[0].url // .[0].host // empty' "$TARGET_DIR/httpx.json" 2>/dev/null || true)
      if [ -n "$FIRST_URL" ]; then
        ffuf -w "$WORDLIST" -u "${FIRST_URL}/FUZZ" -o "$TARGET_DIR/ffuf.json" -of json -t 40 || true
      fi
    fi
  fi

  # 6) Resumen en markdown
  echo "## Recon para $TARGET" > "$TARGET_DIR/report.md"
  echo "- Fecha: $(date -u +"%Y-%m-%d %H:%M:%S UTC")" >> "$TARGET_DIR/report.md"
  [ -f "$TARGET_DIR/subdomains.txt" ] && echo "- Subdominios: $(wc -l < "$TARGET_DIR/subdomains.txt")" >> "$TARGET_DIR/report.md"
  [ -f "$TARGET_DIR/httpx.json" ] && echo "- Hosts HTTP detectados: $(jq -r 'length' "$TARGET_DIR/httpx.json" 2>/dev/null || echo 0)" >> "$TARGET_DIR/report.md"
  [ -f "$TARGET_DIR/nuclei_results.txt" ] && echo "- Hallazgos nuclei: $(wc -l < "$TARGET_DIR/nuclei_results.txt")" >> "$TARGET_DIR/report.md"

  echo "[*] Recon para $TARGET completado. Resultados en $TARGET_DIR"

done < "$TARGET_FILE"

echo "[*] Todo listo. Revisa la carpeta $OUT_ROOT"
