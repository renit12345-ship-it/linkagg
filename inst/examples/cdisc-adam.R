# Real CDISC ADaM data. Needs: install.packages("pharmaverseadam")
if (!"package:linkagg" %in% search()) library(linkagg)
if (!requireNamespace("pharmaverseadam", quietly = TRUE)) {
  stop("This example needs pharmaverseadam: install.packages(\"pharmaverseadam\")")
}

# The pharmaverse build of the CDISC pilot study.
cdisc_adsl <- as.data.frame(pharmaverseadam::adsl)
cdisc_adae <- as.data.frame(pharmaverseadam::adae)
cdisc_adlb <- as.data.frame(pharmaverseadam::adlb)

# Safety population, randomised arms only. Screen failures are not analysed.
cdisc_saf <- cdisc_adsl[cdisc_adsl$SAFFL == "Y" & cdisc_adsl$ARM != "Screen Failure", ]
cdisc_saf$ARM <- factor(trimws(cdisc_saf$ARM),
                  levels = c("Placebo", "Xanomeline Low Dose",
                             "Xanomeline High Dose"))
cdisc_saf <- cdisc_saf[!is.na(cdisc_saf$ARM), ]

# Peak post-baseline ALT and bilirubin, as multiples of the upper limit of
# normal. This is the eDISH construction.
cdisc_peak_xuln <- function(code) {
  d <- cdisc_adlb[cdisc_adlb$PARAMCD == code & !is.na(cdisc_adlb$AVAL) & !is.na(cdisc_adlb$ANRHI) &
              cdisc_adlb$ANRHI > 0, ]
  if (!nrow(d)) return(setNames(numeric(0), character(0)))
  r <- tapply(d$AVAL / d$ANRHI, d$USUBJID, max, na.rm = TRUE)
  r[is.finite(r)]
}
cdisc_alt <- cdisc_peak_xuln("ALT")
cdisc_bili <- cdisc_peak_xuln("BILI")

cdisc_saf$ALT   <- unname(cdisc_alt[cdisc_saf$USUBJID])
cdisc_saf$TBILI <- unname(cdisc_bili[cdisc_saf$USUBJID])
cdisc_saf <- cdisc_saf[is.finite(cdisc_saf$ALT) & is.finite(cdisc_saf$TBILI), ]

# Treatment-emergent adverse events, collapsed to one entry per subject per
# term so a bar counts subjects rather than events.
cdisc_ae <- cdisc_adae[cdisc_adae$USUBJID %in% cdisc_saf$USUBJID &
             !is.na(cdisc_adae$AEBODSYS) & nzchar(cdisc_adae$AEBODSYS), ]
cdisc_ae <- unique(cdisc_ae[, c("USUBJID", "AEBODSYS", "AEDECOD", "AELLT")])

cdisc_split_by_subj <- function(col) {
  s <- split(cdisc_ae[[col]], factor(cdisc_ae$USUBJID, levels = cdisc_saf$USUBJID))
  lapply(s, function(v) if (length(v)) as.character(v) else character(0))
}
# SOC and PT must pair positionally for drill-down, so they are split from the
# same de-duplicated frame in the same order.
cdisc_saf$SOC <- unname(cdisc_split_by_subj("AEBODSYS"))
cdisc_saf$PT  <- unname(cdisc_split_by_subj("AEDECOD"))
cdisc_saf$LLT <- unname(cdisc_split_by_subj("AELLT"))

cat("subjects:", nrow(cdisc_saf), " arms:", nlevels(cdisc_saf$ARM),
    " AE rows:", nrow(cdisc_ae), " distinct PT:", length(unique(cdisc_ae$AEDECOD)), "\n")
print(table(cdisc_saf$ARM))

fig <- linkagg(cdisc_saf, USUBJID) |>
  view_points(TBILI, ALT, log_x = TRUE, log_y = TRUE,
              x_lab = "Peak bilirubin (xULN)", y_lab = "Peak ALT (xULN)",
              zone = list(x = 2, y = 3, label = "Hy's law")) |>
  # Real MedDRA hierarchy: organ class to preferred term to the term the
  # investigator actually reported.
  view_bars(SOC, by = ARM, drill = c(PT, LLT), label = "System organ class") |>
  view_volcano(PT, by = ARM, ref = "Placebo", comp = "Xanomeline High Dose",
               min_n = 5L, label = "Preferred term") |>
  view_table(cols = c("USUBJID", "ARM", "AGE", "SEX", "ALT", "TBILI")) |>
  as_linkagg_widget(
    caption = paste("CDISC pilot study via pharmaverseadam.",
                    "Safety population,", nrow(cdisc_saf), "subjects.",
                    "Peak post-baseline ALT and bilirubin as multiples of ULN."))

# Printing opens it in the RStudio Viewer.
fig
