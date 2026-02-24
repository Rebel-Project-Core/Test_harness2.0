repos <- "https://cloud.r-project.org"
cat("[cran] using repo:", repos, "\n")

ap <- available.packages(repos = repos)
rv <- getRversion()
cat("[cran] R version in this container:", as.character(rv), "\n")
cat("[cran] total packages in repo:", nrow(ap), "\n")

depends <- ap[, "Depends"]
keep <- rep(TRUE, nrow(ap))

for (i in seq_along(depends)) {
  dep <- depends[i]
  if (is.na(dep) || dep == "") next

  m <- regexpr("R *\\(>= *([0-9.]+)\\)", dep)
  if (m > 0) {
    req <- sub(".*R *\\(>= *([0-9.]+)\\).*", "\\1", dep)
    if (numeric_version(req) > rv) {
      keep[i] <- FALSE
    }
  }
}

pkgs <- rownames(ap)[keep]
cat("[cran] packages compatible with R", as.character(rv), ":", length(pkgs), "\n")

writeLines(pkgs, "cran_packages.txt")
