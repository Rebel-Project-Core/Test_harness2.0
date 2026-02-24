#!/bin/bash
set -euo pipefail

############################
# CONFIG
############################
BASE_IMAGE="docker.io/repbioinfo/test_harness"

# Batch id richiesto (es. 2 -> cran_packages_sampled_002.txt)
BATCH_ID="${1:-}"
if [[ -z "$BATCH_ID" ]]; then
  echo "[usage] $0 <BATCH_ID>"
  echo "        es: $0 2    (usa cran_packages_sampled_002.txt)"
  exit 1
fi

BATCH_PADDED="$(printf "%03d" "$BATCH_ID")"
TEST_LIST="cran_packages_sampled_${BATCH_PADDED}.txt"

if [[ ! -f "$TEST_LIST" ]]; then
  echo "[error] Non trovo $TEST_LIST"
  exit 1
fi

# Parallelismo auto: 2*(NCORES-1)
NCORES="$(nproc || echo 1)"
if (( NCORES <= 1 )); then
  N_PARALLEL=1
else
  N_PARALLEL=$(( 2*(NCORES-1) ))
fi
# clamp minimo 1
(( N_PARALLEL < 1 )) && N_PARALLEL=1

CREDO_DIR="results_credo/${BATCH_PADDED}"
BARE_DIR="results_bare/${BATCH_PADDED}"
LOG_DIR="logs/${BATCH_PADDED}"
LOG_FAIL_CREDO="logs/credo_fail/${BATCH_PADDED}"
LOG_FAIL_BARE="logs/bare_fail/${BATCH_PADDED}"

mkdir -p "$CREDO_DIR" "$BARE_DIR" "$LOG_DIR" "$LOG_FAIL_CREDO" "$LOG_FAIL_BARE"

CREDO_OK="$CREDO_DIR/success.txt"
CREDO_FAIL="$CREDO_DIR/fail.txt"
BARE_OK="$BARE_DIR/success.txt"
BARE_FAIL="$BARE_DIR/fail.txt"
PROGRESS_LOG="progress_${BATCH_PADDED}.log"

touch "$CREDO_OK" "$CREDO_FAIL" "$BARE_OK" "$BARE_FAIL" "$PROGRESS_LOG"

log_msg() { echo "$@" | tee -a "$PROGRESS_LOG"; }

wait_for_slot() {
  while (( $(jobs -r | wc -l) >= N_PARALLEL )); do
    sleep 1
  done
}

if ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
  log_msg "[error] Docker image '$BASE_IMAGE' non trovata."
  exit 1
fi

TOTAL=$(wc -l < "$TEST_LIST" | tr -d ' ')
log_msg "[info] Batch: $BATCH_PADDED"
log_msg "[info] Lista test: $TEST_LIST ($TOTAL pacchetti)"
log_msg "[info] Cores: $NCORES -> Parallelismo: $N_PARALLEL"
log_msg "[info] Immagine: $BASE_IMAGE"

already_logged() {
  local pkg="$1" ok_file="$2" fail_file="$3"
  grep -qx "$pkg" "$ok_file" 2>/dev/null && return 0
  grep -qx "$pkg" "$fail_file" 2>/dev/null && return 0
  return 1
}

run_credo_pkg() {
  local idx="$1" pkg="$2"

  if already_logged "$pkg" "$CREDO_OK" "$CREDO_FAIL"; then
    log_msg "[credo] ($idx/$TOTAL) skip $pkg (già testato)"
    return 0
  fi

  log_msg "[credo] ($idx/$TOTAL) INIZIO $pkg"

  docker run --rm \
    -v "$PWD":/work \
    "$BASE_IMAGE" \
    bash -lc "
      set -e

      export CREDO_ENV_DIR=/credo_env
      mkdir -p \"\$CREDO_ENV_DIR\"
      cd \"\$CREDO_ENV_DIR\"

      echo \"[credo] installing (bioconductor) package: $pkg\"
      credo bioconductor $pkg

      echo \"[credo] saving environment\"
      credo save

      echo \"[credo] applying environment\"
      credo apply

      echo \"[credo] testing library load in R\"
      R --slave -e \"pkg <- '$pkg';
                    libdirs <- list.dirs('/credo_env', recursive = TRUE, full.names = TRUE);
                    libdirs <- libdirs[grepl('R-Library$', libdirs)];
                    if (length(libdirs) > 0) .libPaths(c(libdirs, .libPaths()));
                    if (!requireNamespace(pkg, quietly = TRUE)) quit(status = 1) else quit(status = 0)\"
    " >>"$LOG_DIR/credo_${pkg}.log" 2>&1
  local status=$?

  if [[ "$status" -eq 0 ]]; then
    echo "$pkg" >> "$CREDO_OK"
    log_msg "[credo] ($idx/$TOTAL) SUCCESS $pkg"
  else
    echo "$pkg" >> "$CREDO_FAIL"
    cp "$LOG_DIR/credo_${pkg}.log" "$LOG_FAIL_CREDO/" 2>/dev/null || true
    log_msg "[credo] ($idx/$TOTAL) FAIL $pkg (exit code $status)"
  fi
}

run_bare_pkg() {
  local idx="$1" pkg="$2"

  if already_logged "$pkg" "$BARE_OK" "$BARE_FAIL"; then
    log_msg "[bareR] ($idx/$TOTAL) skip $pkg (già testato)"
    return 0
  fi

  log_msg "[bareR] ($idx/$TOTAL) INIZIO $pkg"

  docker run --rm \
    -v "$PWD":/work \
    "$BASE_IMAGE" \
    bash -lc "
      set -e
      cd /work

      R --slave -e \"pkg <- '$pkg';
                    libdir <- '/baseR_lib';
                    dir.create(libdir, recursive = TRUE, showWarnings = FALSE);
                    .libPaths(c(libdir, .libPaths()));
                    if (!requireNamespace('BiocManager', quietly = TRUE)) {
                      install.packages('BiocManager', repos = 'https://cloud.r-project.org');
                    }
                    ok <- TRUE;
                    tryCatch({
                      BiocManager::install(pkg, ask = FALSE, update = FALSE);
                    }, error = function(e) ok <<- FALSE);
                    if (ok && requireNamespace(pkg, quietly = TRUE)) quit(status = 0) else quit(status = 1)\"
    " >>"$LOG_DIR/bare_${pkg}.log" 2>&1
  local status=$?

  if [[ "$status" -eq 0 ]]; then
    echo "$pkg" >> "$BARE_OK"
    log_msg "[bareR] ($idx/$TOTAL) SUCCESS $pkg"
  else
    echo "$pkg" >> "$BARE_FAIL"
    cp "$LOG_DIR/bare_${pkg}.log" "$LOG_FAIL_BARE/" 2>/dev/null || true
    log_msg "[bareR] ($idx/$TOTAL) FAIL $pkg (exit code $status)"
  fi
}

log_msg ""
log_msg "========================================"
log_msg "[step 1] Test CREDO -> $CREDO_DIR"
log_msg "========================================"

i=0
while IFS= read -r pkg_raw; do
  pkg="$(echo "$pkg_raw" | xargs)"
  [[ -z "$pkg" ]] && continue
  i=$((i+1))
  wait_for_slot
  run_credo_pkg "$i" "$pkg" &
done < "$TEST_LIST"
wait

log_msg ""
log_msg "========================================"
log_msg "[step 2] Test bare R -> $BARE_DIR"
log_msg "========================================"

i=0
while IFS= read -r pkg_raw; do
  pkg="$(echo "$pkg_raw" | xargs)"
  [[ -z "$pkg" ]] && continue
  i=$((i+1))
  wait_for_slot
  run_bare_pkg "$i" "$pkg" &
done < "$TEST_LIST"
wait

log_msg ""
log_msg "========================================"
log_msg "[done] Batch $BATCH_PADDED completato."
log_msg "  - CREDO: $CREDO_OK / $CREDO_FAIL"
log_msg "  - bare R: $BARE_OK / $BARE_FAIL"
log_msg "========================================"
