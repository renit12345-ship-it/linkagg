# The Mayo Clinic primary biliary cholangitis trial.
#
# Real patient data from a real randomised trial: D-penicillamine against
# placebo, 1974 to 1984, 312 randomised patients, distributed in the survival
# package as `pbc_raw` and described in Fleming and Harrington (1991). The trial
# found no benefit from D-penicillamine.
#
# Note what the aggregate groups are here. This is not an adverse event
# dataset, so the bars are baseline clinical pbc_findings rather than treated-
# emergent events. The mechanic is the same, each bar stands for many
# patients, but read the clinical content accordingly.
#
# Run it with:  source(system.file("examples/pbc_raw-trial.R", package = "linkagg"))

if (!"package:linkagg" %in% search()) library(linkagg)
if (!requireNamespace("survival", quietly = TRUE)) {
  stop("This example needs survival: install.packages(\"survival\")")
}

pbc_raw <- survival::pbc
pbc_pat <- pbc_raw[!is.na(pbc_raw$trt), ]          # randomised patients only

pbc_pat$ARM <- factor(ifelse(pbc_pat$trt == 1, "D-penicillamine", "Placebo"),
                levels = c("Placebo", "D-penicillamine"))
pbc_pat$SEX <- factor(ifelse(pbc_pat$sex == "f", "Female", "Male"),
                levels = c("Female", "Male"))
pbc_pat$STAGE <- factor(paste("Stage", pbc_pat$stage), levels = paste("Stage", 1:4))
pbc_pat$PATIENT <- sprintf("PBC-%03d", pbc_pat$id)

# One list-column of the clinical pbc_findings present in each patient, which is
# the shape view_bars() and view_volcano() consume. Oedema is graded 0, 0.5
# and 1 in this dataset; anything above zero counts as present.
pbc_findings <- data.frame(
  Ascites       = pbc_pat$ascites == 1,
  Hepatomegaly  = pbc_pat$hepato == 1,
  `Spider naevi` = pbc_pat$spiders == 1,
  Oedema        = pbc_pat$edema > 0,
  `Stage 4 disease` = pbc_pat$stage == 4,
  check.names = FALSE
)
pbc_pat$FINDING <- lapply(seq_len(nrow(pbc_pat)), function(i) {
  nm <- names(pbc_findings)[which(unlist(pbc_findings[i, ]))]
  if (length(nm)) nm else character(0)
})

cat(sprintf("%d randomised patients: %s\n", nrow(pbc_pat),
            paste(sprintf("%s %d", levels(pbc_pat$ARM), table(pbc_pat$ARM)), collapse = ", ")))

fig <- linkagg(pbc_pat, PATIENT) |>
  view_points(bili, ast, log_x = TRUE, log_y = TRUE,
              x_lab = "Serum bilirubin (mg/dL)",
              y_lab = "AST (U/L)",
              # Bilirubin at 2 mg/dL is the prognostic threshold that drives
              # the Mayo risk score; AST at 80 is twice the upper limit of
              # normal. This is a severity region, not a Hy's law region.
              zone = list(x = 2, y = 80, label = "bili >= 2, AST >= 2xULN")) |>
  view_bars(FINDING, by = ARM, label = "Clinical finding") |>
  view_volcano(FINDING, by = ARM, ref = "Placebo", comp = "D-penicillamine",
               min_n = 5L, label = "Clinical finding") |>
  view_table(cols = c("PATIENT", "ARM", "STAGE", "bili", "ast", "albumin")) |>
  as_linkagg_widget(
    caption = paste("Mayo Clinic PBC trial, 312 randomised patients.",
                    "Findings recorded at registration.",
                    "Data: survival::pbc, Fleming & Harrington (1991)."))

fig
