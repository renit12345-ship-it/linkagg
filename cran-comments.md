## Test environments

* local macOS 15.5, R 4.5.3
* R CMD check --as-cran

## R CMD check results

0 errors | 0 warnings | 0 notes

## Notes for the reviewer

This is a first submission.

The package bundles d3 v7.9.0 (ISC licence) under
`inst/htmlwidgets/lib/d3-7.9.0/`, as is usual for an htmlwidget. The library
is unmodified, its licence file is included alongside it, and its author is
credited in `Authors@R` with the `ctb` and `cph` roles.

Examples that would open a browser or start a server are wrapped in
`if (interactive())`.
