# The Mayo Clinic primary biliary cholangitis trial.
#
# Real patient data from a real randomised trial: D-penicillamine against
# placebo, 1974 to 1984, 312 randomised patients, distributed in the survival
# package as `pbc` and described in Fleming and Harrington (1991). The trial
# found no benefit from D-penicillamine.
#
# Note what the aggregate groups are here. This is not an adverse event
# dataset, so the bars are baseline clinical findings rather than treated-
# emergent events. The mechanic is the same — each bar stands for many
# patients — but read the clinical content accordingly.
#
# Run it with:  source(system.file("examples/pbc-trial.R", package = "linkagg"))

if (!"package:linkagg" %in% search()) library(linkagg)
if (!requireNamespace("survival", quietly = TRUE)) {
  stop("This example needs survival: install.packages(\"survival\")")
}

pbc <- survival::pbc
d <- pbc[!is.na(pbc$trt), ]          # randomised patients only

d$ARM <- factor(ifelse(d$trt == 1, "D-penicillamine", "Placebo"),
                levels = c("Placebo", "D-penicillamine"))
d$SEX <- factor(ifelse(d$sex == "f", "Female", "Male"),
                levels = c("Female", "Male"))
d$STAGE <- factor(paste("Stage", d$stage), levels = paste("Stage", 1:4))
d$PATIENT <- sprintf("PBC-%03d", d$id)

# One list-column of the clinical findings present in each patient, which is
# the shape view_bars() and view_volcano() consume. Oedema is graded 0, 0.5
# and 1 in this dataset; anything above zero counts as present.
findings <- data.frame(
  Ascites       = d$ascites == 1,
  Hepatomegaly  = d$hepato == 1,
  `Spider naevi` = d$spiders == 1,
  Oedema        = d$edema > 0,
  `Stage 4 disease` = d$stage == 4,
  check.names = FALSE
)
d$FINDING <- lapply(seq_len(nrow(d)), function(i) {
  nm <- names(findings)[which(unlist(findings[i, ]))]
  if (length(nm)) nm else character(0)
})

cat(sprintf("%d randomised patients: %s\n", nrow(d),
            paste(sprintf("%s %d", levels(d$ARM), table(d$ARM)), collapse = ", ")))

fig <- linkagg(d, PATIENT) |>
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
