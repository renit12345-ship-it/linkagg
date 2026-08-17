#' Run the Shiny demo app
#'
#' Launches a small app showing the figure wired into Shiny, with the current
#' selection read back in R from `input$fig_selected` and summarised below the
#' figure. Use it as a working reference for the Shiny bindings, which are
#' documented at [linkagg-shiny].
#'
#' @param ... Passed to [shiny::runApp()], for example `port` or `launch.browser`.
#'
#' @return Called for its side effect of running the app.
#'
#' @examples
#' if (interactive()) {
#'   run_linkagg_app()
#' }
#'
#' @export
run_linkagg_app <- function(...) {
  miss <- Filter(function(p) !requireNamespace(p, quietly = TRUE),
                 c("shiny", "bslib"))
  if (length(miss)) {
    stop("The demo app needs: ", paste(miss, collapse = ", "),
         ". Install with install.packages(c(\"",
         paste(miss, collapse = "\", \""), "\")).", call. = FALSE)
  }
  dir <- system.file("shiny", package = "linkagg")
  if (!nzchar(dir)) {
    stop("Demo app not found. Reinstall linkagg.", call. = FALSE)
  }
  shiny::runApp(dir, ...)
}
