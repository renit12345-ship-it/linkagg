#' @keywords internal
"_PACKAGE"

`%||%` <- function(a, b) if (is.null(a)) b else a

# Accept a bare column name, a character string, or any expression that
# evaluates to one. The last case is what makes the views usable from Shiny,
# where the column is chosen at runtime and arrives as `input$something`.
# A bare name is still taken literally, so a stray variable of the same name
# cannot silently redirect a column reference.
col_name <- function(q, env = parent.frame()) {
  if (is.null(q))      return(NULL)
  if (is.character(q)) return(as.character(q))
  if (is.name(q))      return(as.character(q))
  val <- tryCatch(eval(q, env), error = function(e) NULL)
  # An expression that evaluates to NULL means "no column", which is how an
  # optional facet or arm is switched off from calling code.
  if (is.null(val)) return(NULL)
  if (is.character(val) && length(val) == 1L && !is.na(val)) return(val)
  deparse(q)
}

check_spec <- function(spec) {
  if (!inherits(spec, "linkagg_spec")) {
    stop("Expected a linkagg spec. Start the chain with linkagg().", call. = FALSE)
  }
  invisible(TRUE)
}

check_cols <- function(spec, cols) {
  miss <- setdiff(cols, names(spec$data))
  if (length(miss)) {
    stop("Column not found in data: ", paste(miss, collapse = ", "), call. = FALSE)
  }
  invisible(TRUE)
}

#' Start a linked figure
#'
#' Begins a specification. Add displays with [view_points()], [view_bars()] and
#' [view_table()], then render with [as_linkagg_widget()].
#'
#' @param data A data frame with one row per unit of selection. For clinical
#'   safety use this is a subject-level dataset such as ADSL, one row per
#'   subject, restricted to the analysis population.
#' @param key Column uniquely identifying each row, such as `USUBJID`. Bare
#'   name or string.
#' @param threads Draw animated threads from selected rows to the groups they
#'   belong to. This is what makes the row-to-aggregate mapping visible. Set
#'   `FALSE` for a quieter figure.
#' @param thread_cap Maximum threads drawn. Above this, threads are sampled
#'   evenly so the display stays legible.
#' @param points Renderer for the row-level display: `"auto"` switches to
#'   canvas above `canvas_threshold` rows, `"svg"` and `"canvas"` force one.
#' @param canvas_threshold Row count above which `"auto"` uses canvas.
#' @param palette Named list of colours overriding the default light theme.
#'   Recognised names: `ground`, `panel`, `data`, `select`, `zone`, `text`,
#'   `dim`, `rule`, `mute` for marks outside the selection, and `arms` for a
#'   vector of one colour per treatment arm. Arm colours default to an
#'   Okabe-Ito derived set that survives colour blindness and greyscale
#'   printing, with a neutral first colour for placebo.
#'
#' @return An object of class `linkagg_spec`.
#'
#' @examples
#' set.seed(1)
#' adsl <- data.frame(
#'   USUBJID = sprintf("01-%03d", 1:120),
#'   ARM     = rep(c("Placebo", "Drug A 50mg", "Drug A 100mg"), each = 40),
#'   ALT     = exp(rnorm(120)),
#'   TBILI   = exp(rnorm(120))
#' )
#' adsl$SOC <- replicate(120, sample(c("Hepatobiliary disorders",
#'                                     "Investigations",
#'                                     "Gastrointestinal disorders"),
#'                                   sample(0:3, 1)), simplify = FALSE)
#'
#' linkagg(adsl, USUBJID) |>
#'   view_points(TBILI, ALT, log_x = TRUE, log_y = TRUE) |>
#'   view_bars(SOC, by = ARM) |>
#'   view_table(cols = c("USUBJID", "ARM", "ALT", "TBILI"))
#'
#' @export
linkagg <- function(data, key, threads = TRUE, thread_cap = 160L,
                    points = c("auto", "svg", "canvas"),
                    canvas_threshold = 6000L, palette = NULL) {
  key <- col_name(substitute(key), parent.frame())
  points <- match.arg(points)
  if (!is.data.frame(data)) stop("`data` must be a data frame.", call. = FALSE)
  if (!nrow(data))          stop("`data` has no rows.", call. = FALSE)

  spec <- structure(
    list(
      data  = data,
      key   = key,
      views = list(),
      options = list(
        threads         = isTRUE(threads),
        threadCap       = as.integer(thread_cap),
        pointRenderer   = points,
        canvasThreshold = as.integer(canvas_threshold),
        palette         = palette %||% list()
      )
    ),
    class = "linkagg_spec"
  )
  check_cols(spec, key)

  if (anyDuplicated(data[[key]])) {
    stop("`key` must be unique: ", key, " has duplicates. ",
         "Pass a subject-level dataset, not an events dataset.", call. = FALSE)
  }
  spec
}

#' Add a row-level scatter display
#'
#' One mark per row, and the display you brush to make a selection. For liver
#' safety this is the eDISH shape: peak ALT against peak total bilirubin on log
#' scales, with a reference region.
#'
#' @param spec A `linkagg_spec`.
#' @param x,y Numeric columns. Bare names or strings.
#' @param log_x,log_y Use a log scale on that axis.
#' @param x_lab,y_lab Axis labels. Default to the column names.
#' @param zone Optional threshold region drawn behind the data, as a list with
#'   `x` and `y` numeric cut-points and an optional `label`. Marks above both
#'   cut-points fall inside the region.
#'
#' @param facet Optional column giving one small multiple per level, drawn on
#'   shared scales so panels are comparable. Brushing acts within one panel.
#'   With `facet_row` also set, this becomes the column variable of a grid.
#' @param facet_row Optional second column, laid out down the rows to give a
#'   full grid of panels: one column per level of `facet`, one row per level
#'   of `facet_row`, such as arm across and sex down. Scales stay shared across
#'   the whole grid, so every panel is comparable with every other, and a brush
#'   still selects only the rows in the one cell you dragged over.
#' @param facet_levels,facet_row_levels Optional character vectors fixing the
#'   order of columns and of rows.
#' @return The updated `linkagg_spec`.
#' @export
view_points <- function(spec, x, y, log_x = FALSE, log_y = FALSE,
                        x_lab = NULL, y_lab = NULL, zone = NULL,
                        facet = NULL, facet_levels = NULL,
                        facet_row = NULL, facet_row_levels = NULL) {
  x <- col_name(substitute(x), parent.frame())
  y <- col_name(substitute(y), parent.frame())
  facet_q <- substitute(facet)
  facet <- if (is.null(facet_q)) NULL else col_name(facet_q, parent.frame())
  frow_q <- substitute(facet_row)
  facet_row <- if (is.null(frow_q)) NULL else col_name(frow_q, parent.frame())
  check_spec(spec)
  check_cols(spec, c(x, y))
  if (!is.null(facet)) check_cols(spec, facet)
  if (!is.null(facet_row)) {
    check_cols(spec, facet_row)
    if (is.null(facet)) {
      stop("`facet_row` needs `facet` as well: a grid needs both a column ",
           "variable and a row variable.", call. = FALSE)
    }
  }

  for (nm in c(x, y)) {
    if (!is.numeric(spec$data[[nm]])) {
      stop("view_points() needs numeric columns; `", nm, "` is not.", call. = FALSE)
    }
  }
  if (!is.null(zone) && !all(c("x", "y") %in% names(zone))) {
    stop("`zone` must be a list with elements `x` and `y`.", call. = FALSE)
  }

  flv <- NULL; fix <- NULL; rlv <- NULL
  if (!is.null(facet)) {
    fa <- facet_axis(spec$data[[facet]], facet_levels)
    flv <- fa$levels
    fix <- fa$index
    if (all(fix < 0)) stop("No values of `", facet, "` matched `facet_levels`.",
                           call. = FALSE)

    if (!is.null(facet_row)) {
      ra <- facet_axis(spec$data[[facet_row]], facet_row_levels)
      rlv <- ra$levels
      if (all(ra$index < 0)) {
        stop("No values of `", facet_row, "` matched `facet_row_levels`.",
             call. = FALSE)
      }
      # One panel per (row, column) cell, numbered row-major. The drawing and
      # brushing code already keys on a single panel index, so a grid needs no
      # separate code path: cell = row * n_columns + column.
      nC <- length(flv)
      fix <- ifelse(fix < 0L | ra$index < 0L, -1L, ra$index * nC + fix)
      fix <- as.integer(fix)
    }
  }

  spec$views <- c(spec$views, list(list(
    type = "points", x = x, y = y,
    xlog = isTRUE(log_x), ylog = isTRUE(log_y),
    xlab = x_lab %||% x, ylab = y_lab %||% y,
    zone = zone,
    facet = facet, facetLevels = flv, facetIndex = fix,
    facetRow = facet_row, facetRowLevels = rlv
  )))
  spec
}

# Levels for a facetting column, and each row's zero-based position in them.
facet_axis <- function(col, levels) {
  lv <- levels %||%
    (if (is.factor(col)) base::levels(col) else sort(unique(as.character(col))))
  lv <- as.character(lv)
  ix <- match(as.character(col), lv) - 1L
  list(levels = lv, index = as.integer(ifelse(is.na(ix), -1L, ix)))
}

# Resolve the denominator for each level of `by`.
resolve_population <- function(population, data, by, by_levels) {
  if (is.null(population)) {
    tab <- table(as.character(data[[by]]))
    out <- as.numeric(tab[by_levels])
  } else if (is.data.frame(population)) {
    if (!by %in% names(population)) {
      stop("`population` must contain the `by` column: ", by, call. = FALSE)
    }
    tab <- table(as.character(population[[by]]))
    out <- as.numeric(tab[by_levels])
  } else if (is.numeric(population)) {
    if (is.null(names(population))) {
      stop("`population` must be a named numeric vector.", call. = FALSE)
    }
    out <- as.numeric(population[by_levels])
  } else {
    stop("`population` must be NULL, a named numeric vector, or a data frame.",
         call. = FALSE)
  }

  out[is.na(out)] <- 0
  if (any(out <= 0)) {
    bad <- by_levels[out <= 0]
    stop("Population size is zero or missing for: ", paste(bad, collapse = ", "),
         ". Percentages would be undefined.", call. = FALSE)
  }
  out
}

#' Add an aggregate bar display, optionally split by treatment arm
#'
#' One bar per group, each standing for many rows. When a selection is active
#' each bar fills to the share of its own rows that are selected, which is the
#' behaviour existing linked-brushing tools in R do not provide.
#'
#' Supply `by` to split every group by treatment arm, which is how safety
#' displays are actually read. With `by` set, bar length is the percentage of
#' that arm's analysis population, matching the denominator convention of a
#' standard adverse event summary. Without `by`, bar length is a raw count.
#'
#' @param spec A `linkagg_spec`.
#' @param group Grouping column. Either an ordinary column with one value per
#'   row, or a list-column where each element is a character vector, for rows
#'   in several groups at once, such as a subject with events in several system
#'   organ classes.
#' @param by Optional column giving the treatment arm, one value per row.
#' @param group_levels Optional character vector fixing the order of groups.
#'   Defaults to descending overall count.
#' @param by_levels Optional character vector fixing the order of arms.
#'   Defaults to the factor levels, or sorted unique values.
#' @param denominator `"population"` gives percentages of each arm's analysis
#'   population; `"count"` gives raw counts. Defaults to `"population"` when
#'   `by` is supplied and `"count"` otherwise.
#' @param population Denominator source. `NULL` counts rows per arm in `data`,
#'   which is correct when `data` is the analysis population. Otherwise pass a
#'   named numeric vector such as `c(Placebo = 80, "Drug A" = 82)`, or the full
#'   population data frame to count from.
#' @param drill Optional finer term to drill into, such as preferred term
#'   below system organ class. Must be shaped like `group`: if `group` is a
#'   list-column, `drill` must be a list-column whose elements pair up
#'   positionally, so element `j` of `drill[[i]]` is the term for element `j`
#'   of `group[[i]]`.
#' @param label Display title. Defaults to the column name.
#'
#' @return The updated `linkagg_spec`.
#' @export
view_bars <- function(spec, group, by = NULL, drill = NULL,
                      group_levels = NULL, by_levels = NULL,
                      denominator = c("population", "count"),
                      population = NULL, label = NULL) {
  group <- col_name(substitute(group), parent.frame())
  by_q  <- substitute(by)
  by    <- if (is.null(by_q)) NULL else col_name(by_q, parent.frame())
  dr_q  <- substitute(drill)
  drill <- if (is.null(dr_q)) NULL else col_name(dr_q, parent.frame())

  check_spec(spec)
  check_cols(spec, group)
  if (!is.null(by))    check_cols(spec, by)
  if (!is.null(drill)) check_cols(spec, drill)

  denominator <- if (missing(denominator)) {
    if (is.null(by)) "count" else "population"
  } else {
    match.arg(denominator)
  }
  if (is.null(by) && denominator == "population") {
    stop("`denominator = \"population\"` needs `by` so each arm has a denominator.",
         call. = FALSE)
  }

  col <- spec$data[[group]]
  vals <- if (is.list(col)) {
    lapply(col, function(v) as.character(v[!is.na(v)]))
  } else {
    lapply(as.character(col), function(v) if (is.na(v)) character(0) else v)
  }

  lv <- group_levels
  if (is.null(lv)) {
    tab <- table(unlist(vals, use.names = FALSE))
    lv <- names(sort(tab, decreasing = TRUE))
  }
  if (!length(lv)) stop("`group` has no non-missing values.", call. = FALSE)

  membership <- lapply(vals, function(v) {
    ix <- match(v, lv)
    as.integer(ix[!is.na(ix)] - 1L)   # zero-based for the JavaScript side
  })

  # Drill terms pair positionally with group entries, and must survive the
  # same NA filtering the group entries went through.
  drillLevels <- NULL; drillIdx <- NULL
  if (!is.null(drill)) {
    dcol <- spec$data[[drill]]
    dvals <- if (is.list(dcol)) {
      lapply(dcol, function(v) as.character(v))
    } else {
      lapply(as.character(dcol), function(v) v)
    }
    if (is.list(col) != is.list(dcol)) {
      stop("`drill` must be shaped like `group`: both list-columns, or neither.",
           call. = FALSE)
    }
    bad <- which(lengths(dvals) != lengths(vals))
    if (length(bad)) {
      stop("`drill` and `group` must pair up element by element. ",
           "Row ", bad[1], " has ", lengths(vals)[bad[1]], " group entries but ",
           lengths(dvals)[bad[1]], " drill entries.", call. = FALSE)
    }
    drillLevels <- sort(unique(unlist(dvals, use.names = FALSE)))
    drillIdx <- Map(function(gv, dv) {
      keep <- !is.na(match(gv, lv))
      as.integer(match(dv[keep], drillLevels) - 1L)
    }, vals, dvals)
    drillIdx <- lapply(drillIdx, function(z) as.integer(ifelse(is.na(z), -1L, z)))
  }

  nG <- length(lv)

  if (is.null(by)) {
    totals <- integer(nG)
    for (ix in membership) for (k in ix) totals[k + 1L] <- totals[k + 1L] + 1L

    view <- list(
      type = "bars", group = group, by = NULL,
      levels = as.character(lv), byLevels = NULL,
      membership = unname(membership), armIndex = NULL,
      cellTotals = as.integer(totals), denom = NULL,
      denominator = "count", label = label %||% group,
      drill = drill, drillLevels = drillLevels, drillIdx = unname(drillIdx)
    )
  } else {
    arm <- spec$data[[by]]
    blv <- by_levels %||%
      (if (is.factor(arm)) levels(arm) else sort(unique(as.character(arm))))
    blv <- as.character(blv)
    nA  <- length(blv)

    armIx <- match(as.character(arm), blv) - 1L   # zero-based, NA if unmatched
    if (all(is.na(armIx))) {
      stop("No values of `", by, "` matched `by_levels`.", call. = FALSE)
    }

    cell <- integer(nG * nA)                      # row-major: g * nA + a
    for (i in seq_along(membership)) {
      a <- armIx[i]
      if (is.na(a)) next
      for (k in membership[[i]]) {
        p <- k * nA + a + 1L
        cell[p] <- cell[p] + 1L
      }
    }

    denom <- if (denominator == "population") {
      resolve_population(population, spec$data, by, blv)
    } else NULL

    view <- list(
      type = "bars", group = group, by = by,
      levels = as.character(lv), byLevels = blv,
      membership = unname(membership),
      armIndex = as.integer(ifelse(is.na(armIx), -1L, armIx)),
      cellTotals = as.integer(cell),
      denom = denom,
      denominator = denominator,
      label = label %||% group,
      drill = drill, drillLevels = drillLevels, drillIdx = unname(drillIdx)
    )
  }

  spec$views <- c(spec$views, list(view))
  spec
}

#' Add a row listing
#'
#' Shows every row, and filters to the selection when one is active.
#'
#' @param spec A `linkagg_spec`.
#' @param cols Character vector of columns to show. Defaults to all columns
#'   that are not list-columns.
#' @param labels Optional column headings, same length as `cols`.
#' @param max_rows Rows rendered at once. The count shown is always the full
#'   selection size.
#'
#' @return The updated `linkagg_spec`.
#' @export
view_table <- function(spec, cols = NULL, labels = NULL, max_rows = 400L) {
  check_spec(spec)
  if (is.null(cols)) {
    cols <- names(spec$data)[!vapply(spec$data, is.list, logical(1))]
  }
  cols <- as.character(cols)
  check_cols(spec, cols)
  if (!is.null(labels) && length(labels) != length(cols)) {
    stop("`labels` must be the same length as `cols`.", call. = FALSE)
  }

  spec$views <- c(spec$views, list(list(
    type = "table", cols = cols,
    labels = as.character(labels %||% cols),
    maxRows = as.integer(max_rows)
  )))
  spec
}

#' Add a linked histogram
#'
#' Bins a continuous column and draws it as an aggregate display. This is the
#' case crosstalk's documentation names as unsupported, since each bar stands
#' for many rows. Here a selection fills each bar from the baseline up, in
#' proportion to the rows of that bin which are selected.
#'
#' @param spec A `linkagg_spec`.
#' @param x Numeric column to bin. Bare name or string.
#' @param bins Number of equal-width bins.
#' @param by Optional treatment arm column, drawn as one series per arm.
#' @param log Bin on the log10 scale, for skewed measures such as lab ratios.
#'   Non-positive values are dropped, and the count of dropped rows is checked
#'   rather than passed over silently.
#' @param denominator `"count"` or `"population"`, as in [view_bars()].
#' @param population Denominator source, as in [view_bars()].
#' @param label Display title. Defaults to the column name.
#'
#' @return The updated `linkagg_spec`.
#' @export
view_hist <- function(spec, x, bins = 24L, by = NULL, log = FALSE,
                      denominator = c("count", "population"),
                      population = NULL, label = NULL) {
  x    <- col_name(substitute(x), parent.frame())
  by_q <- substitute(by)
  by   <- if (is.null(by_q)) NULL else col_name(by_q, parent.frame())

  check_spec(spec)
  check_cols(spec, x)
  if (!is.null(by)) check_cols(spec, by)

  denominator <- if (missing(denominator)) "count" else match.arg(denominator)
  if (is.null(by) && denominator == "population") {
    stop("`denominator = \"population\"` needs `by`.", call. = FALSE)
  }

  v <- spec$data[[x]]
  if (!is.numeric(v)) stop("view_hist() needs a numeric column; `", x,
                           "` is not.", call. = FALSE)

  bins <- as.integer(bins)
  if (bins < 2L) stop("`bins` must be at least 2.", call. = FALSE)

  vv <- as.numeric(v)
  if (isTRUE(log)) {
    n_bad <- sum(!is.na(vv) & vv <= 0)
    if (n_bad) {
      warning(n_bad, " non-positive value(s) in `", x,
              "` dropped for log binning.", call. = FALSE)
    }
    vv[!is.na(vv) & vv <= 0] <- NA_real_
    vv <- log10(vv)
  }

  fin <- is.finite(vv)
  if (!any(fin)) stop("`", x, "` has no finite values to bin.", call. = FALSE)
  rng <- range(vv[fin])
  if (rng[2] <= rng[1]) rng[2] <- rng[1] + 1

  breaks <- seq(rng[1], rng[2], length.out = bins + 1L)
  binIx <- findInterval(vv, breaks, rightmost.closed = TRUE, all.inside = FALSE) - 1L
  binIx[!fin | binIx < 0L | binIx >= bins] <- -1L
  binIx <- as.integer(binIx)

  nA <- 1L; blv <- NULL; armIx <- NULL; denom <- NULL
  if (!is.null(by)) {
    arm <- spec$data[[by]]
    blv <- if (is.factor(arm)) levels(arm) else sort(unique(as.character(arm)))
    blv <- as.character(blv)
    nA  <- length(blv)
    armIx <- match(as.character(arm), blv) - 1L
    armIx <- as.integer(ifelse(is.na(armIx), -1L, armIx))
    if (denominator == "population") {
      denom <- resolve_population(population, spec$data, by, blv)
    }
  }

  cell <- integer(bins * nA)
  for (i in seq_along(binIx)) {
    b <- binIx[i]
    if (b < 0L) next
    a <- if (is.null(armIx)) 0L else armIx[i]
    if (a < 0L) next
    p <- b * nA + a + 1L
    cell[p] <- cell[p] + 1L
  }

  spec$views <- c(spec$views, list(list(
    type = "hist", x = x, by = by, log = isTRUE(log),
    bins = bins, breaks = as.numeric(breaks),
    binIndex = binIx, byLevels = blv, armIndex = armIx,
    cellTotals = as.integer(cell), denom = denom,
    denominator = denominator,
    label = label %||% x,
    dropped = as.integer(sum(binIx < 0L))
  )))
  spec
}
