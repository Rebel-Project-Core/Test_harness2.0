# REBEL Test Harness 2.0

Reproducible benchmarking framework for evaluating REBEL installation success rates against standard BiocManager installation on randomly sampled CRAN packages.

This repository contains all scripts, data, and results needed to independently reproduce the empirical validation reported in:

> Martelli E. et al. "FAIR REBEL: Reproducible Environment Builder for Explicit Library Resolution." GigaScience (submitted).

---

## Repository Structure

```
.
├── generate_cran_list.R          # Generates list of CRAN packages compatible with container R version
├── sampleBatches.sh              # Random sampling of packages into batches
├── runMe_batch.sh                # Executes REBEL and Bare tests in parallel Docker containers
├── cran_packages_sampled.txt     # Exact list of 1,000 packages used in the paper
├── Rebel/                        # REBEL test results (success.txt, fail.txt)
├── bare/                         # Bare installation test results (success.txt, fail.txt)
└── README.md
```

---

## Requirements

- Docker (tested with Docker 24+)
- Bash
- The REBEL test harness Docker image: `docker.io/repbioinfo/test_harness`

Pull the image before running:

```bash
docker pull docker.io/repbioinfo/test_harness
```

---

## Reproducing the Paper Results

To reproduce the exact experiment reported in the paper, run the test harness on the provided package list:

```bash
bash runMe_batch.sh 1
```

This will test all 1,000 packages in `cran_packages_sampled.txt` under both conditions (REBEL and Bare), using one isolated Docker container per package per condition. Results are written to `results_credo/` and `results_bare/`.

**Note:** Full execution requires significant compute time depending on available CPU cores. The script automatically parallelizes across `2 * (nproc - 1)` cores.

---

## Generating a New Sample

To generate a new random sample of CRAN packages compatible with the container R version:

**Step 1:** Generate the full compatible package list inside the Docker container:

```bash
docker run --rm -v "$PWD":/work docker.io/repbioinfo/test_harness \
    bash -lc "cd /work && R -q -f generate_cran_list.R"
```

This produces `cran_packages.txt`.

**Step 2:** Sample a batch of 1,000 packages:

```bash
bash sampleBatches.sh 1000
```

This produces a new `cran_packages_sampled_001.txt`.

**Step 3:** Run the benchmark on the new batch:

```bash
bash runMe_batch.sh 1
```

---

## Defining Success

A package is considered successfully installed if and only if it can be loaded via `requireNamespace()` in R after the installation procedure:

- **Bare condition:** installation via `BiocManager::install()` with updates disabled, followed by `requireNamespace()`.
- **REBEL condition:** full `rebel install` + `rebel save` + `rebel apply` workflow, followed by `requireNamespace()` from the offline archive.

Each test runs in a freshly created Docker container that is destroyed immediately after the attempt, ensuring complete isolation between tests.

---

## Results Summary

| Condition | Successes | Failures |
|-----------|-----------|----------|
| Bare (BiocManager) | 672 / 1,000 (67.2%) | 328 / 1,000 |
| REBEL | 756 / 1,000 (75.6%) | 244 / 1,000 |

Of the 328 packages that failed under Bare installation, REBEL recovered 84 (25.6%). An additional 66 packages (27.0% of remaining failures) were resolved by the AI-driven harness, bringing cumulative recovery to 150/328 (45.7%).

---

## Citation

If you use this test harness in your work, please cite:

> Martelli E. et al. "FAIR REBEL: Reproducible Environment Builder for Explicit Library Resolution." GigaScience (submitted).

And the repository itself:

> Rebel-Project-Core. Test_harness2.0. GitHub. https://github.com/Rebel-Project-Core/Test_harness2.0

---

## License

This repository is released under the MIT License.
