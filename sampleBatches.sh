#!/bin/bash
set -euo pipefail

CRAN_LIST="cran_packages.txt"
BATCH_SIZE="${1:-1000}"          # default 1000; puoi passare un numero diverso
OUT_PREFIX="cran_packages_sampled_"
OUT_DIR="."

if [[ ! -f "$CRAN_LIST" ]]; then
  echo "[error] Non trovo $CRAN_LIST. Generala prima (generate_cran_list.R / step 1)."
  exit 1
fi

tmp_all="$(mktemp)"
tmp_used="$(mktemp)"
tmp_remaining="$(mktemp)"
trap 'rm -f "$tmp_all" "$tmp_used" "$tmp_remaining"' EXIT

# normalizza lista completa
awk 'NF{gsub(/^[ \t]+|[ \t]+$/,""); print}' "$CRAN_LIST" | sort -u > "$tmp_all"

# raccoglie TUTTI i già-samplati (qualsiasi file cran_packages_sampled*.txt)
# (se non esistono, tmp_used resta vuoto)
: > "$tmp_used"
shopt -s nullglob
for f in "${OUT_DIR}/${OUT_PREFIX}"*.txt cran_packages_sampled.txt; do
  [[ -f "$f" ]] || continue
  awk 'NF{gsub(/^[ \t]+|[ \t]+$/,""); print}' "$f" >> "$tmp_used"
done
shopt -u nullglob
sort -u "$tmp_used" -o "$tmp_used"

# calcola remaining = all - used
comm -23 "$tmp_all" "$tmp_used" > "$tmp_remaining"

total_all=$(wc -l < "$tmp_all" | tr -d ' ')
total_used=$(wc -l < "$tmp_used" | tr -d ' ')
total_rem=$(wc -l < "$tmp_remaining" | tr -d ' ')

echo "[info] Totale pacchetti in $CRAN_LIST: $total_all"
echo "[info] Già presenti in sampled*: $total_used"
echo "[info] Rimanenti da batchare: $total_rem"
echo "[info] Batch size: $BATCH_SIZE"

if (( total_rem == 0 )); then
  echo "[done] Non c'è nulla da fare: tutti i pacchetti risultano già inclusi in qualche sampled."
  exit 0
fi

# decide da che indice partire: massimo indice già esistente + 1, oppure 1
max_idx=0
for f in "${OUT_DIR}/${OUT_PREFIX}"*.txt; do
  base="$(basename "$f")"
  # match _NNN
  if [[ "$base" =~ ${OUT_PREFIX}([0-9]{3})\.txt$ ]]; then
    n="${BASH_REMATCH[1]}"
    # 10#$n per evitare interpretazione ottale
    (( 10#$n > max_idx )) && max_idx=$((10#$n))
  fi
done

start_idx=$((max_idx + 1))
echo "[info] Primo indice batch che genero: $(printf "%03d" "$start_idx")"

# crea batch finché ci sono righe
idx="$start_idx"
while true; do
  rem=$(wc -l < "$tmp_remaining" | tr -d ' ')
  (( rem == 0 )) && break

  out_file="${OUT_DIR}/${OUT_PREFIX}$(printf "%03d" "$idx").txt"
  # se il file esiste già (strano ma possibile), salto avanti
  if [[ -f "$out_file" ]]; then
    echo "[warn] $out_file esiste già, salto."
    idx=$((idx+1))
    continue
  fi

  # prendi un campione random di BATCH_SIZE dalla remaining
  # se remaining < BATCH_SIZE, prendi tutto
  if (( rem <= BATCH_SIZE )); then
    cp "$tmp_remaining" "$out_file"
    : > "$tmp_remaining"
    echo "[batch] creato $out_file (ultima tranche: $rem pkgs)"
  else
    shuf "$tmp_remaining" | head -n "$BATCH_SIZE" > "$out_file"
    # rimuovi dal remaining quelli appena selezionati
    comm -23 <(sort -u "$tmp_remaining") <(sort -u "$out_file") > "${tmp_remaining}.new"
    mv "${tmp_remaining}.new" "$tmp_remaining"
    echo "[batch] creato $out_file ($BATCH_SIZE pkgs)"
  fi

  idx=$((idx+1))
done

echo "[done] Batch generation completata."
