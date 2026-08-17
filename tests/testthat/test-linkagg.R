test_that("linkagg() validates its inputs", {
  df <- data.frame(id = c("a", "b"), v = c(1, 2))

  expect_s3_class(linkagg(df, id), "linkagg_spec")
  expect_s3_class(linkagg(df, "id"), "linkagg_spec")

  expect_error(linkagg(list(a = 1), id), "data frame")
  expect_error(linkagg(df[0, ], id), "no rows")
  expect_error(linkagg(df, nope), "Column not found")
  expect_error(linkagg(data.frame(id = c("a", "a"), v = 1:2), id), "unique")
})

test_that("view_points() requires numeric columns", {
  df <- data.frame(id = c("a", "b"), v = c(1, 2), lab = c("x", "y"))
  expect_error(linkagg(df, id) |> view_points(v, lab), "numeric")
  expect_silent(linkagg(df, id) |> view_points(v, v))
})

test_that("view_bars() resolves single-membership columns", {
  df <- data.frame(
    id  = sprintf("s%02d", 1:6),
    soc = c("A", "B", "A", "C", "A", "B"),
    stringsAsFactors = FALSE
  )
  spec <- linkagg(df, id) |> view_bars(soc)
  v <- spec$views[[1]]

  expect_equal(v$levels, c("A", "B", "C"))          # descending count
  expect_equal(v$cellTotals, c(3L, 2L, 1L))
  expect_equal(v$membership[[1]], 0L)               # zero-based for JS
  expect_equal(v$membership[[4]], 2L)
  expect_equal(sum(v$cellTotals), length(unlist(v$membership)))
})

test_that("view_bars() handles rows belonging to several groups", {
  df <- data.frame(id = c("s1", "s2", "s3"), stringsAsFactors = FALSE)
  df$soc <- list(c("A", "B"), character(0), c("B", "C", "A"))

  spec <- linkagg(df, id) |> view_bars(soc)
  v <- spec$views[[1]]

  expect_equal(sort(v$levels), c("A", "B", "C"))
  expect_equal(v$cellTotals[match("A", v$levels)], 2L)
  expect_equal(v$cellTotals[match("C", v$levels)], 1L)
  expect_length(v$membership[[2]], 0L)              # empty stays empty
})

test_that("view_bars() honours an explicit level order", {
  df <- data.frame(id = c("a", "b", "c"), g = c("x", "y", "x"),
                   stringsAsFactors = FALSE)
  v <- (linkagg(df, id) |> view_bars(g, group_levels = c("y", "x")))$views[[1]]
  expect_equal(v$levels, c("y", "x"))
  expect_equal(v$cellTotals, c(1L, 2L))
})

test_that("view_bars() drops values outside the supplied levels", {
  df <- data.frame(id = c("a", "b"), g = c("x", "zz"), stringsAsFactors = FALSE)
  v <- (linkagg(df, id) |> view_bars(g, group_levels = "x"))$views[[1]]
  expect_equal(v$cellTotals, 1L)
  expect_length(v$membership[[2]], 0L)
})

test_that("view_table() defaults exclude list-columns", {
  df <- data.frame(id = c("a", "b"), v = c(1, 2), stringsAsFactors = FALSE)
  df$soc <- list("A", "B")
  v <- (linkagg(df, id) |> view_table())$views[[1]]
  expect_equal(v$cols, c("id", "v"))
  expect_error(linkagg(df, id) |> view_table(cols = "id", labels = c("a", "b")),
               "same length")
})

test_that("rendering needs at least one view", {
  df <- data.frame(id = c("a", "b"), v = c(1, 2))
  expect_error(as_linkagg_widget(linkagg(df, id)), "at least one view")
})

test_that("the widget payload carries only the columns it needs", {
  skip_if_not_installed("htmlwidgets")
  df <- data.frame(id = sprintf("s%d", 1:5), a = 1:5, b = 6:10, extra = 11:15,
                   g = c("x", "y", "x", "y", "x"), stringsAsFactors = FALSE)
  w <- linkagg(df, id) |>
    view_points(a, b) |>
    view_bars(g) |>
    view_table(cols = c("id", "a")) |>
    as_linkagg_widget()

  expect_s3_class(w, "htmlwidget")
  expect_setequal(names(w$x$cols), c("id", "a", "b"))
  expect_false("extra" %in% names(w$x$cols))
  expect_equal(w$x$n, 5L)
  expect_equal(w$x$key, "id")
})

# ---- treatment arm splits and denominators --------------------------------

make_adsl <- function() {
  df <- data.frame(
    USUBJID = sprintf("01-%03d", 1:9),
    ARM = c("Placebo", "Placebo", "Placebo",
            "Low", "Low", "Low",
            "High", "High", "High"),
    stringsAsFactors = FALSE
  )
  df$SOC <- list(
    c("A", "B"), "A", character(0),
    "B", c("A", "B"), "B",
    c("A", "B"), "A", "A"
  )
  df
}

test_that("view_bars() splits cells by arm correctly", {
  v <- (linkagg(make_adsl(), USUBJID) |>
          view_bars(SOC, by = ARM, group_levels = c("A", "B"),
                    by_levels = c("Placebo", "Low", "High")))$views[[1]]

  expect_equal(v$byLevels, c("Placebo", "Low", "High"))
  # cellTotals is row-major: group * n_arms + arm
  # A: Placebo 2, Low 1, High 3   B: Placebo 1, Low 3, High 1
  expect_equal(v$cellTotals, c(2L, 1L, 3L, 1L, 3L, 1L))
  expect_equal(sum(v$cellTotals), length(unlist(v$membership)))
})

test_that("denominators default to the analysis population per arm", {
  v <- (linkagg(make_adsl(), USUBJID) |>
          view_bars(SOC, by = ARM, by_levels = c("Placebo", "Low", "High")))$views[[1]]
  expect_equal(v$denom, c(3, 3, 3))
  expect_equal(v$denominator, "population")
})

test_that("an explicit population overrides the row counts", {
  v <- (linkagg(make_adsl(), USUBJID) |>
          view_bars(SOC, by = ARM,
                    by_levels = c("Placebo", "Low", "High"),
                    population = c(Placebo = 40, Low = 41, High = 39)))$views[[1]]
  expect_equal(v$denom, c(40, 41, 39))
})

test_that("a population data frame is counted, not taken as sizes", {
  pop <- data.frame(ARM = rep(c("Placebo", "Low", "High"), times = c(5, 6, 7)),
                    stringsAsFactors = FALSE)
  v <- (linkagg(make_adsl(), USUBJID) |>
          view_bars(SOC, by = ARM, by_levels = c("Placebo", "Low", "High"),
                    population = pop))$views[[1]]
  expect_equal(v$denom, c(5, 6, 7))
})

test_that("a missing or zero denominator is an error, not a silent NaN", {
  expect_error(
    linkagg(make_adsl(), USUBJID) |>
      view_bars(SOC, by = ARM, by_levels = c("Placebo", "Low", "High"),
                population = c(Placebo = 40, Low = 41)),
    "zero or missing"
  )
})

test_that("percentages cannot exceed 100 with the population denominator", {
  v <- (linkagg(make_adsl(), USUBJID) |> view_bars(SOC, by = ARM))$views[[1]]
  nA <- length(v$byLevels)
  pct <- v$cellTotals / rep(v$denom, times = length(v$levels)) * 100
  expect_true(all(pct <= 100))
})

test_that("population denominators need an arm", {
  expect_error(
    linkagg(make_adsl(), USUBJID) |> view_bars(SOC, denominator = "population"),
    "needs `by`"
  )
})

test_that("armIndex marks unmatched arms as -1 rather than dropping rows", {
  v <- (linkagg(make_adsl(), USUBJID) |>
          view_bars(SOC, by = ARM, by_levels = c("Placebo", "Low"),
                    population = c(Placebo = 3, Low = 3)))$views[[1]]
  expect_equal(sum(v$armIndex == -1L), 3L)   # the three High subjects
  expect_equal(sum(v$cellTotals), 7L)        # their memberships excluded
})

# ---- faceting --------------------------------------------------------------

test_that("view_points() resolves facet levels and index", {
  df <- data.frame(id = letters[1:6], a = 1:6, b = 6:1,
                   grp = c("x", "y", "x", "z", "y", "x"),
                   stringsAsFactors = FALSE)
  v <- (linkagg(df, id) |> view_points(a, b, facet = grp))$views[[1]]
  expect_equal(v$facetLevels, c("x", "y", "z"))
  expect_equal(v$facetIndex, c(0L, 1L, 0L, 2L, 1L, 0L))
})

test_that("rows outside the supplied facet levels are marked, not dropped", {
  df <- data.frame(id = letters[1:4], a = 1:4, b = 4:1,
                   grp = c("x", "y", "zz", "x"), stringsAsFactors = FALSE)
  v <- (linkagg(df, id) |>
          view_points(a, b, facet = grp, facet_levels = c("x", "y")))$views[[1]]
  expect_equal(v$facetIndex, c(0L, 1L, -1L, 0L))
  expect_error(
    linkagg(df, id) |> view_points(a, b, facet = grp, facet_levels = "nope"),
    "matched"
  )
})

grid_df <- function() {
  data.frame(
    id  = sprintf("s%d", 1:6),
    a   = as.numeric(1:6),
    b   = as.numeric(6:1),
    arm = c("P", "A", "P", "A", "P", "A"),
    sex = c("F", "F", "M", "M", "F", "M"),
    stringsAsFactors = FALSE
  )
}

test_that("view_points() numbers grid panels row-major", {
  v <- (linkagg(grid_df(), id) |>
          view_points(a, b, facet = arm, facet_row = sex))$views[[1]]

  expect_equal(v$facetLevels, c("A", "P"))     # columns
  expect_equal(v$facetRowLevels, c("F", "M"))  # rows

  # cell = row * n_columns + column, so F/P = 0*2+1 = 1 and M/A = 1*2+0 = 2.
  expect_equal(v$facetIndex, c(1L, 0L, 3L, 2L, 1L, 2L))

  # Every panel index must decode back to the subject's own arm and sex.
  d <- grid_df()
  nC <- length(v$facetLevels)
  expect_equal(v$facetLevels[v$facetIndex %% nC + 1L], d$arm)
  expect_equal(v$facetRowLevels[v$facetIndex %/% nC + 1L], d$sex)
})

test_that("a grid cell is unassigned if either variable is unmatched", {
  v <- (linkagg(grid_df(), id) |>
          view_points(a, b, facet = arm, facet_row = sex,
                      facet_row_levels = "F"))$views[[1]]
  # The three male subjects fall outside the supplied row levels.
  expect_equal(v$facetIndex, c(1L, 0L, -1L, -1L, 1L, -1L))
})

test_that("columns can be chosen at runtime, as Shiny inputs are", {
  d <- grid_df()
  pick <- list(col = "arm", row = "sex")   # stands in for input$...

  v <- (linkagg(d, id) |>
          view_points(a, b, facet = pick$col, facet_row = pick$row))$views[[1]]
  expect_equal(v$facet, "arm")
  expect_equal(v$facetRow, "sex")

  # An expression evaluating to NULL means "no facet row", so calling code can
  # switch the grid off without building a different call.
  none <- NULL
  v2 <- (linkagg(d, id) |>
           view_points(a, b, facet = pick$col,
                       facet_row = if (is.null(none)) NULL else none))$views[[1]]
  expect_null(v2$facetRow)
  expect_null(v2$facetRowLevels)

  # A bare name still wins over a same-named variable in scope.
  arm <- "sex"
  v3 <- (linkagg(d, id) |> view_points(a, b, facet = arm))$views[[1]]
  expect_equal(v3$facet, "arm")

  # Plain strings and variables holding strings both resolve.
  v4 <- (linkagg(d, id) |> view_bars("arm"))$views[[1]]
  expect_equal(v4$group, "arm")

  # A bare symbol is always the column name itself, never the variable's value,
  # so `sex` here means the sex column even though `sex` also holds "arm".
  sex <- "arm"
  v5 <- (linkagg(d, id) |> view_bars(pick$col, by = sex))$views[[1]]
  expect_equal(v5$group, "arm")
  expect_equal(v5$by, "sex")

  # Wrapping in parentheses makes it an expression, so the value is used.
  v6 <- (linkagg(d, id) |> view_bars(pick$col, by = (sex)))$views[[1]]
  expect_equal(v6$by, "arm")
})

test_that("view_points() rejects a row variable with no column variable", {
  expect_error(linkagg(grid_df(), id) |> view_points(a, b, facet_row = sex),
               "needs `facet`")
  expect_error(
    linkagg(grid_df(), id) |>
      view_points(a, b, facet = arm, facet_row = sex, facet_row_levels = "zz"),
    "matched"
  )
})

# ---- drill-down ------------------------------------------------------------

drill_df <- function() {
  df <- data.frame(USUBJID = sprintf("s%d", 1:4), ARM = c("P", "P", "A", "A"),
                   stringsAsFactors = FALSE)
  df$SOC <- list(c("Hepatobiliary", "GI"), "Hepatobiliary", "GI",
                 c("Hepatobiliary", "GI"))
  df$PT  <- list(c("ALT increased", "Nausea"), "Jaundice", "Nausea",
                 c("ALT increased", "Vomiting"))
  df
}

test_that("drill terms pair positionally with group entries", {
  v <- (linkagg(drill_df(), USUBJID) |>
          view_bars(SOC, by = ARM, drill = PT))$views[[1]]
  expect_equal(sort(v$drillLevels[[1]]),
               sort(c("ALT increased", "Jaundice", "Nausea", "Vomiting")))
  expect_equal(lengths(v$drillIdx[[1]]), lengths(v$pairGroup))
  expect_true(all(unlist(v$drillIdx[[1]]) >= 0))
})

test_that("mismatched drill lengths are rejected", {
  df <- drill_df()
  df$PT[[1]] <- "ALT increased"       # one term for two SOC entries
  expect_error(
    linkagg(df, USUBJID) |> view_bars(SOC, by = ARM, drill = PT),
    "element by element"
  )
})

test_that("drill must be shaped like group", {
  df <- drill_df()
  df$PT <- c("a", "b", "c", "d")      # plain column against a list-column
  expect_error(
    linkagg(df, USUBJID) |> view_bars(SOC, by = ARM, drill = PT),
    "shaped like"
  )
})

# ---- histogram -------------------------------------------------------------

test_that("view_hist() bins every finite value exactly once", {
  df <- data.frame(id = sprintf("s%d", 1:100), v = seq(1, 100),
                   arm = rep(c("P", "A"), 50), stringsAsFactors = FALSE)
  v <- (linkagg(df, id) |> view_hist(v, bins = 10))$views[[1]]
  expect_length(v$breaks, 11L)
  expect_equal(sum(v$cellTotals), 100L)
  expect_true(all(v$binIndex >= 0L & v$binIndex < 10L))
  expect_equal(v$dropped, 0L)
})

test_that("view_hist() splits bins by arm with correct totals", {
  df <- data.frame(id = sprintf("s%d", 1:100), v = seq(1, 100),
                   arm = rep(c("P", "A"), 50), stringsAsFactors = FALSE)
  v <- (linkagg(df, id) |> view_hist(v, bins = 5, by = arm))$views[[1]]
  expect_equal(length(v$cellTotals), 5L * 2L)
  expect_equal(sum(v$cellTotals), 100L)
})

test_that("log binning drops non-positive values and says so", {
  df <- data.frame(id = sprintf("s%d", 1:10), v = c(-1, 0, 1:8),
                   stringsAsFactors = FALSE)
  expect_warning(
    v <- (linkagg(df, id) |> view_hist(v, bins = 4, log = TRUE))$views[[1]],
    "non-positive"
  )
  expect_equal(v$dropped, 2L)
  expect_equal(sum(v$cellTotals), 8L)
})

test_that("view_hist() validates its inputs", {
  df <- data.frame(id = c("a", "b"), v = c(1, 2), lab = c("x", "y"),
                   stringsAsFactors = FALSE)
  expect_error(linkagg(df, id) |> view_hist(lab), "numeric")
  expect_error(linkagg(df, id) |> view_hist(v, bins = 1), "at least 2")
  expect_error(linkagg(df, id) |> view_hist(v, denominator = "population"),
               "needs `by`")
})

# ---- volcano ---------------------------------------------------------------

vol_df <- function() {
  # 4 on placebo, 4 on active. "Nausea" hits 1 placebo and 3 active.
  df <- data.frame(
    id  = sprintf("v%d", 1:8),
    arm = rep(c("Placebo", "Active"), each = 4),
    stringsAsFactors = FALSE
  )
  df$PT <- list(
    "Nausea", character(0), "Rash", character(0),
    c("Nausea", "Rash"), "Nausea", "Nausea", character(0)
  )
  df
}

test_that("view_volcano() computes the risk difference against the reference", {
  v <- (linkagg(vol_df(), id) |>
          view_volcano(PT, by = arm, ref = "Placebo", comp = "Active",
                       min_n = 1L))$views[[1]]

  i <- match("Nausea", v$levels)
  expect_equal(v$countRef[i], 1L)          # 1 of 4 placebo
  expect_equal(v$countComp[i], 3L)         # 3 of 4 active
  expect_equal(v$nRef, 4L)
  expect_equal(v$nComp, 4L)
  expect_equal(v$riskDiff[i], 50)          # 75% - 25%, in percentage points

  # Sign follows the comparison arm: Rash is 1 active vs 1 placebo, so zero.
  j <- match("Rash", v$levels)
  expect_equal(v$riskDiff[j], 0)

  # p-value agrees with a direct Fisher test on the same table.
  expect_equal(v$pValue[i],
               stats::fisher.test(matrix(c(3, 1, 1, 3), nrow = 2))$p.value)
})

test_that("view_volcano() counts each subject once per term", {
  v <- (linkagg(vol_df(), id) |>
          view_volcano(PT, by = arm, min_n = 1L))$views[[1]]
  # cellTotals is subjects, not events, so it can never exceed the two arms.
  expect_true(all(v$cellTotals <= v$nRef + v$nComp))
  expect_equal(v$cellTotals[match("Nausea", v$levels)], 4L)   # 1 + 3
  # Membership indices stay inside the kept terms.
  expect_true(all(unlist(v$membership) < length(v$levels)))
  expect_true(all(unlist(v$membership) >= 0))
})

test_that("view_volcano() excludes arms outside the comparison", {
  df <- vol_df()
  df$arm[1:2] <- "Other"        # these two must take no part
  v <- (linkagg(df, id) |>
          view_volcano(PT, by = arm, ref = "Placebo", comp = "Active",
                       min_n = 1L))$views[[1]]
  expect_equal(v$nRef, 2L)
  expect_equal(v$armIndex[1:2], c(-1L, -1L))
  expect_length(v$membership[[1]], 0L)
})

test_that("view_volcano() reports rather than hides sparse terms", {
  v <- (linkagg(vol_df(), id) |>
          view_volcano(PT, by = arm, min_n = 4L))$views[[1]]
  expect_equal(v$dropped, 1L)            # Rash has 2 subjects, below 4
  expect_false("Rash" %in% v$levels)
  expect_true("Nausea" %in% v$levels)
})

test_that("view_volcano() validates its arms", {
  d <- vol_df()
  expect_error(linkagg(d, id) |> view_volcano(PT, by = arm, ref = "Nope"),
               "Arm not found")
  expect_error(
    linkagg(d, id) |> view_volcano(PT, by = arm, ref = "Active", comp = "Active"),
    "must be different"
  )
  expect_error(linkagg(d, id) |> view_volcano(PT, by = arm, min_n = 99L),
               "No term reaches")
})

# ---- subject counting ------------------------------------------------------

test_that("a subject listed twice under one group counts once", {
  # An events dataset carries one row per preferred term, and several terms
  # share a system organ class, so the collapsed list-column repeats the SOC.
  df <- data.frame(id = c("s1", "s2"), arm = c("A", "A"),
                   stringsAsFactors = FALSE)
  df$SOC <- list(c("GI", "GI", "GI"), c("GI", "Skin"))

  v <- (linkagg(df, id) |> view_bars(SOC))$views[[1]]
  gi <- match("GI", v$levels)
  expect_equal(v$cellTotals[gi], 2L)          # two subjects, not four
  expect_equal(sort(v$membership[[1]]), gi - 1L)
  expect_length(v$membership[[1]], 1L)
})

test_that("a bar can never exceed its own denominator", {
  set.seed(3)
  n <- 60
  df <- data.frame(id = sprintf("s%02d", 1:n),
                   arm = rep(c("P", "A"), each = n / 2),
                   stringsAsFactors = FALSE)
  # Every subject repeats one SOC several times, the shape that produced a
  # bar reading over 100% on real ADaM data.
  df$SOC <- lapply(seq_len(n), function(i) rep("GI", sample(1:6, 1)))

  v <- (linkagg(df, id) |> view_bars(SOC, by = arm))$views[[1]]
  nA <- length(v$byLevels)
  pct <- v$cellTotals / rep(v$denom, times = length(v$levels)) * 100
  expect_true(all(pct <= 100))
  expect_equal(sum(v$cellTotals), n)
})

test_that("drill-down still pairs correctly after de-duplication", {
  df <- data.frame(id = c("s1", "s2"), arm = c("A", "B"),
                   stringsAsFactors = FALSE)
  df$SOC <- list(c("GI", "GI"), "GI")
  df$PT  <- list(c("Nausea", "Vomiting"), "Nausea")

  v <- (linkagg(df, id) |> view_bars(SOC, by = arm, drill = PT))$views[[1]]
  expect_equal(v$cellTotals[match("GI", v$levels) ], 1L)  # s1 counted once
  # pairGroup keeps both entries so the drill terms stay aligned.
  expect_length(v$pairGroup[[1]], 2L)
  expect_length(v$drillIdx[[1]], 2L)
  expect_length(v$membership[[1]], 1L)
  expect_equal(sort(v$drillLevels[[1]]), c("Nausea", "Vomiting"))
})

# ---- multi-level drill-down ------------------------------------------------

hier_df <- function() {
  df <- data.frame(id = c("s1", "s2", "s3"), arm = c("A", "A", "B"),
                   stringsAsFactors = FALSE)
  df$SOC <- list(c("Cardiac", "Cardiac"), "Cardiac", "Skin")
  df$PT  <- list(c("MI", "MI"), "MI", "Rash")
  df$LLT <- list(c("Inferior MI", "Septal MI"), "Inferior MI", "Redness")
  df
}

test_that("view_bars() accepts a hierarchy of drill columns", {
  v <- (linkagg(hier_df(), id) |>
          view_bars(SOC, by = arm, drill = c(PT, LLT)))$views[[1]]

  expect_equal(v$drill, c("PT", "LLT"))
  expect_length(v$drillLevels, 2L)             # one level set per depth
  expect_equal(v$drillLevels[[1]], c("MI", "Rash"))   # all PTs, sorted
  expect_equal(sort(v$drillLevels[[2]]),
               c("Inferior MI", "Redness", "Septal MI"))
  expect_length(v$drillIdx, 2L)

  # Each depth stays aligned entry by entry with pairGroup.
  for (k in seq_along(v$drillIdx)) {
    expect_equal(lengths(v$drillIdx[[k]]), lengths(v$pairGroup))
  }
})

test_that("strings and bare names both work for a drill hierarchy", {
  a <- (linkagg(hier_df(), id) |>
          view_bars(SOC, drill = c(PT, LLT)))$views[[1]]
  b <- (linkagg(hier_df(), id) |>
          view_bars(SOC, drill = c("PT", "LLT")))$views[[1]]
  expect_equal(a$drill, b$drill)
  expect_equal(a$drillLevels, b$drillLevels)
})

test_that("a single drill column still yields one level, not a flat vector", {
  v <- (linkagg(hier_df(), id) |> view_bars(SOC, drill = PT))$views[[1]]
  expect_equal(v$drill, "PT")
  expect_length(v$drillLevels, 1L)
  expect_equal(v$drillLevels[[1]], c("MI", "Rash"))
})

test_that("every drill level must pair with the group element by element", {
  df <- hier_df()
  df$LLT[[1]] <- "Inferior MI"          # one entry where the group has two
  expect_error(
    linkagg(df, id) |> view_bars(SOC, drill = c(PT, LLT)),
    "pair up element by element"
  )
  expect_error(
    linkagg(df, id) |> view_bars(SOC, drill = c(PT, arm)),
    "shaped like `group`"
  )
})

test_that("subjects reaching a deep term are recoverable from the indices", {
  v <- (linkagg(hier_df(), id) |>
          view_bars(SOC, drill = c(PT, LLT)))$views[[1]]
  gi <- match("Cardiac", v$levels) - 1L
  pi <- match("MI", v$drillLevels[[1]]) - 1L
  li <- match("Septal MI", v$drillLevels[[2]]) - 1L

  # Walk Cardiac > MI > Septal MI and collect the subjects, the way the
  # display resolves a drill path.
  on_path <- vapply(seq_len(3), function(i) {
    g <- v$pairGroup[[i]]; p <- v$drillIdx[[1]][[i]]; l <- v$drillIdx[[2]][[i]]
    any(g == gi & p == pi & l == li)
  }, logical(1))
  expect_equal(which(on_path), 1L)      # only s1 had a septal MI
})
