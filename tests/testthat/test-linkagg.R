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
  expect_equal(sort(v$drillLevels),
               sort(c("ALT increased", "Jaundice", "Nausea", "Vomiting")))
  expect_equal(lengths(v$drillIdx), lengths(v$membership))
  expect_true(all(unlist(v$drillIdx) >= 0))
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
