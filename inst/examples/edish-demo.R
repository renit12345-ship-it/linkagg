# A worked eDISH-shaped example: brush the liver corner, watch the adverse
# event bars fill to the share of each arm that the selection covers.
#
# Run it with:  source(system.file("examples/edish-demo.R", package = "linkagg"))

# Works whether linkagg is installed or loaded with devtools::load_all().
if (!"linkagg" %in% loadedNamespaces()) library(linkagg)

set.seed(42)
n <- 240
socs <- c("Hepatobiliary disorders", "Investigations",
          "Gastrointestinal disorders", "Skin and subcutaneous tissue disorders")
pts <- list(
  "Hepatobiliary disorders" = c("Hyperbilirubinaemia", "Cholestasis", "Hepatitis"),
  "Investigations" = c("ALT increased", "AST increased", "Blood bilirubin increased"),
  "Gastrointestinal disorders" = c("Nausea", "Diarrhoea", "Vomiting"),
  "Skin and subcutaneous tissue disorders" = c("Rash", "Pruritus")
)

# Subject-level, one row per subject, as ADSL would be.
adsl <- data.frame(
  USUBJID = sprintf("01-%03d", seq_len(n)),
  ARM     = factor(rep(c("Placebo", "Drug A 50mg", "Drug A 100mg"), each = n / 3),
                   levels = c("Placebo", "Drug A 50mg", "Drug A 100mg")),
  ALT     = exp(rnorm(n, 0.2, 0.9)),
  TBILI   = exp(rnorm(n, -0.1, 0.8)),
  stringsAsFactors = FALSE
)

# SOC and PT are paired list-columns: element j of PT is the preferred term for
# element j of SOC, which is what view_bars(drill = ) requires.
soc_col <- vector("list", n)
pt_col  <- vector("list", n)
for (i in seq_len(n)) {
  k <- sample(0:3, 1)
  s <- if (k == 0) character(0) else sample(socs, k)
  soc_col[[i]] <- s
  pt_col[[i]]  <- if (!length(s)) character(0)
                  else vapply(s, function(z) sample(pts[[z]], 1), character(1),
                              USE.NAMES = FALSE)
}
adsl$SOC <- soc_col
adsl$PT  <- pt_col

fig <- linkagg(adsl, USUBJID) |>
  view_points(TBILI, ALT, log_x = TRUE, log_y = TRUE,
              x_lab = "Peak TBILI (xULN)", y_lab = "Peak ALT (xULN)",
              zone = list(x = 2, y = 3, label = "Hy's law")) |>
  view_bars(SOC, by = ARM, drill = PT) |>
  view_hist(ALT, bins = 24, by = ARM, log = TRUE) |>
  view_table(cols = c("USUBJID", "ARM", "ALT", "TBILI")) |>
  as_linkagg_widget(caption = "Simulated data, 240 subjects")

# Printing opens it in the RStudio Viewer.
fig
