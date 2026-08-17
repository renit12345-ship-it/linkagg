# Real CDISC ADaM data. Needs: install.packages("pharmaverseadam")
if (!"package:linkagg" %in% search()) library(linkagg)
if (!requireNamespace("pharmaverseadam", quietly = TRUE)) {
  stop("This example needs pharmaverseadam: install.packages(\"pharmaverseadam\")")
}

# The pharmaverse build of the CDISC pilot study.
adsl <- as.data.frame(pharmaverseadam::adsl)
adae <- as.data.frame(pharmaverseadam::adae)
adlb <- as.data.frame(pharmaverseadam::adlb)

# Safety population, randomised arms only. Screen failures are not analysed.
saf <- adsl[adsl$SAFFL == "Y" & adsl$ARM != "Screen Failure", ]
saf$ARM <- factor(trimws(saf$ARM),
                  levels = c("Placebo", "Xanomeline Low Dose",
                             "Xanomeline High Dose"))
saf <- saf[!is.na(saf$ARM), ]

# Peak post-baseline ALT and bilirubin, as multiples of the upper limit of
# normal. This is the eDISH construction.
peak_xuln <- function(code) {
  d <- adlb[adlb$PARAMCD == code & !is.na(adlb$AVAL) & !is.na(adlb$ANRHI) &
              adlb$ANRHI > 0, ]
  if (!nrow(d)) return(setNames(numeric(0), character(0)))
  r <- tapply(d$AVAL / d$ANRHI, d$USUBJID, max, na.rm = TRUE)
  r[is.finite(r)]
}
alt <- peak_xuln("ALT")
bili <- peak_xuln("BILI")

saf$ALT   <- unname(alt[saf$USUBJID])
saf$TBILI <- unname(bili[saf$USUBJID])
saf <- saf[is.finite(saf$ALT) & is.finite(saf$TBILI), ]

# Treatment-emergent adverse events, collapsed to one entry per subject per
# term so a bar counts subjects rather than events.
ae <- adae[adae$USUBJID %in% saf$USUBJID &
             !is.na(adae$AEBODSYS) & nzchar(adae$AEBODSYS), ]
ae <- unique(ae[, c("USUBJID", "AEBODSYS", "AEDECOD", "AELLT")])

split_by_subj <- function(col) {
  s <- split(ae[[col]], factor(ae$USUBJID, levels = saf$USUBJID))
  lapply(s, function(v) if (length(v)) as.character(v) else character(0))
}
# SOC and PT must pair positionally for drill-down, so they are split from the
# same de-duplicated frame in the same order.
saf$SOC <- unname(split_by_subj("AEBODSYS"))
saf$PT  <- unname(split_by_subj("AEDECOD"))
saf$LLT <- unname(split_by_subj("AELLT"))

cat("subjects:", nrow(saf), " arms:", nlevels(saf$ARM),
    " AE rows:", nrow(ae), " distinct PT:", length(unique(ae$AEDECOD)), "\n")
print(table(saf$ARM))

fig <- linkagg(saf, USUBJID) |>
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
                    "Safety population,", nrow(saf), "subjects.",
                    "Peak post-baseline ALT and bilirubin as multiples of ULN."))

# Printing opens it in the RStudio Viewer.
fig
