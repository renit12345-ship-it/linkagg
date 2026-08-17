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
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("The demo app needs shiny. Install it with install.packages(\"shiny\").",
         call. = FALSE)
  }
  dir <- system.file("shiny", package = "linkagg")
  if (!nzchar(dir)) {
    stop("Demo app not found. Reinstall linkagg.", call. = FALSE)
  }
  shiny::runApp(dir, ...)
}
