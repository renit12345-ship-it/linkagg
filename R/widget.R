#' Render a linked figure
#'
#' Builds the `htmlwidget`. Save it with [htmlwidgets::saveWidget()] and
#' `selfcontained = TRUE` to get a single HTML file that opens offline with no
#' server, which is the point of the package.
#'
#' @param spec A `linkagg_spec`, or an already-built widget, returned unchanged.
#' @param width,height Widget dimensions. `height` defaults to a size that fits
#'   the displays you added, including one sub-bar per treatment arm.
#' @param caption Optional free text shown in the footer, for example the
#'   dataset and any subset applied.
#' @param stamp Add a provenance line recording the render time, package
#'   version, row count and per-arm denominators. Keep this on for anything you
#'   intend to share or archive.
#' @param elementId Optional DOM id.
#'
#' @return An object of class `htmlwidget`.
#' @export
as_linkagg_widget <- function(spec, width = NULL, height = NULL,
                              caption = NULL, stamp = TRUE, elementId = NULL) {
  if (inherits(spec, "htmlwidget")) return(spec)
  check_spec(spec)
  if (!length(spec$views)) {
    stop("Add at least one view before rendering.", call. = FALSE)
  }

  needed <- unique(unlist(lapply(spec$views, function(v) {
    switch(v$type,
      points = c(v$x, v$y),
      table  = v$cols,
      bars   = if (is.null(v$by)) character(0) else v$by,
      character(0))
  })))
  needed <- unique(c(spec$key, needed))

  cols <- lapply(spec$data[needed], function(col) {
    if (is.factor(col)) as.character(col) else col
  })
  names(cols) <- needed

  prov <- NULL
  if (isTRUE(stamp)) {
    bar1 <- Filter(function(v) v$type == "bars", spec$views)
    dpart <- ""
    if (length(bar1) && !is.null(bar1[[1]]$denom)) {
      dpart <- paste0("  |  N = ",
        paste(sprintf("%s %d", bar1[[1]]$byLevels, as.integer(bar1[[1]]$denom)),
              collapse = ", "))
    }
    prov <- paste0(
      format(Sys.time(), "%Y-%m-%d %H:%M %Z"),
      "  |  linkagg ", as.character(utils::packageVersion("linkagg")),
      "  |  ", nrow(spec$data), " rows", dpart)
  }

  payload <- list(
    key     = spec$key,
    n       = nrow(spec$data),
    cols    = cols,
    views   = spec$views,
    options = c(spec$options, list(caption = caption, provenance = prov))
  )

  if (is.null(height)) {
    bars <- Filter(function(v) v$type == "bars", spec$views)
    nG <- if (length(bars)) length(bars[[1]]$levels) else 0
    nA <- if (length(bars) && !is.null(bars[[1]]$byLevels))
            length(bars[[1]]$byLevels) else 1
    has_tb <- any(vapply(spec$views, function(v) v$type == "table", logical(1)))
    barsH  <- 90 + nG * (16 + nA * 14 + 14)
    height <- max(500, barsH + 70) + (if (has_tb) 300 else 0)
  }

  htmlwidgets::createWidget(
    name = "linkagg",
    x = payload,
    width = width,
    height = height,
    package = "linkagg",
    elementId = elementId,
    sizingPolicy = htmlwidgets::sizingPolicy(
      defaultWidth = "100%",
      defaultHeight = height,
      browser.fill = TRUE,
      viewer.fill = TRUE,
      padding = 0
    )
  )
}

#' @export
print.linkagg_spec <- function(x, ...) {
  print(as_linkagg_widget(x), ...)
  invisible(x)
}

#' @export
format.linkagg_spec <- function(x, ...) {
  types <- vapply(x$views, function(v) v$type, character(1))
  sprintf("<linkagg_spec> %d rows, key `%s`, views: %s",
          nrow(x$data), x$key,
          if (length(types)) paste(types, collapse = ", ") else "none yet")
}

#' Shiny bindings for linkagg
#'
#' The current selection is reported as `input$<outputId>_selected`, a character
#' vector of key values, or `NULL` when nothing is selected.
#'
#' @param outputId Output variable name.
#' @param width,height Passed to the container.
#' @param expr An expression producing a `linkagg_spec` or widget.
#' @param env Environment in which to evaluate `expr`.
#' @param quoted Is `expr` already quoted?
#'
#' @return `linkaggOutput()` returns a Shiny output element;
#'   `renderLinkagg()` returns a Shiny render function.
#'
#' @name linkagg-shiny
#' @export
linkaggOutput <- function(outputId, width = "100%", height = "760px") {
  htmlwidgets::shinyWidgetOutput(outputId, "linkagg", width, height,
                                 package = "linkagg")
}

#' @rdname linkagg-shiny
#' @export
renderLinkagg <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) expr <- substitute(expr)
  expr <- as.call(list(quote(linkagg::as_linkagg_widget), expr))
  htmlwidgets::shinyRenderWidget(expr, linkaggOutput, env, quoted = TRUE)
}
