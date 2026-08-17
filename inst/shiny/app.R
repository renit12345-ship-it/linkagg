# linkagg inside Shiny.
#
# Two directions are on show here. Shiny drives the figure: the sidebar
# controls rebuild it, including the facet grid. The figure drives Shiny: the
# current selection arrives as input$fig_selected and every card below the
# figure, and the download, is computed in R from that vector.
#
# Launch it with linkagg::run_linkagg_app().

# Test the search path, not loadedNamespaces(): calling this app through
# linkagg::run_linkagg_app() loads the namespace without attaching it, so the
# exported linkaggOutput() and renderLinkagg() would not be findable here.
# devtools::load_all() attaches too, so this covers the development loop.
if (!"package:linkagg" %in% search()) library(linkagg)
library(shiny)
library(bslib, warn.conflicts = FALSE)

set.seed(42)
n <- 300
socs <- c("Hepatobiliary disorders", "Investigations",
          "Gastrointestinal disorders", "Skin and subcutaneous tissue disorders")

adsl <- data.frame(
  USUBJID = sprintf("01-%03d", seq_len(n)),
  ARM     = factor(rep(c("Placebo", "Drug A 50mg", "Drug A 100mg"), each = n / 3),
                   levels = c("Placebo", "Drug A 50mg", "Drug A 100mg")),
  SEX     = factor(sample(c("Male", "Female"), n, TRUE),
                   levels = c("Male", "Female")),
  AGEGR1  = factor(sample(c("<65", ">=65"), n, TRUE), levels = c("<65", ">=65")),
  ALT     = exp(rnorm(n, 0.2, 0.9)),
  TBILI   = exp(rnorm(n, -0.1, 0.8)),
  stringsAsFactors = FALSE
)
adsl$SOC <- replicate(n, sample(socs, sample(0:3, 1)), simplify = FALSE)

# System fonts only. A web font would need a network call, which defeats the
# offline-forever claim the package is built around.
SANS <- paste(
  "-apple-system, BlinkMacSystemFont, 'Segoe UI', Inter, Roboto,",
  "'Helvetica Neue', Arial, sans-serif"
)

theme <- bs_theme(
  version = 5, bg = "#FFFFFF", fg = "#101828", primary = "#1D4ED8",
  base_font = SANS, heading_font = SANS,
  "body-bg" = "#F8FAFC", "border-color" = "#E3E8EF",
  "card-border-radius" = "12px", "card-cap-bg" = "#FFFFFF"
)

css <- HTML("
  body { font-variant-numeric: tabular-nums; }
  .card { box-shadow: 0 1px 2px rgba(16,24,40,.05); }
  .card-header {
    font-size: 12px; font-weight: 600; letter-spacing: .05em;
    text-transform: uppercase; color: #667085;
    border-bottom: 1px solid #E3E8EF; padding: 12px 18px;
  }
  .lk-eyebrow {
    font-size: 11px; font-weight: 600; letter-spacing: .08em;
    text-transform: uppercase; color: #667085; margin: 0 0 4px;
  }
  .lk-title {
    font-size: 24px; font-weight: 650; letter-spacing: -.02em;
    color: #101828; margin: 0 0 6px;
  }
  .lk-lede { font-size: 14.5px; line-height: 1.6; color: #475467;
             max-width: 78ch; margin: 0 0 22px; }
  .lk-lede code { background: #F1F5F9; color: #1D4ED8; padding: 1px 6px;
                  border-radius: 5px; font-size: 12.5px; }
  .lk-stat { padding: 16px 18px; }
  .lk-stat .lab { font-size: 11px; font-weight: 600; letter-spacing: .06em;
                  text-transform: uppercase; color: #667085; margin-bottom: 6px; }
  .lk-stat .val { font-size: 26px; font-weight: 650; letter-spacing: -.02em;
                  color: #101828; line-height: 1.15; }
  .lk-stat .sub { font-size: 12.5px; color: #667085; margin-top: 3px; }
  table.lk-tbl { width: 100%; border-collapse: collapse; font-size: 13.5px; }
  table.lk-tbl th {
    text-align: left; font-size: 10.5px; font-weight: 600; letter-spacing: .06em;
    text-transform: uppercase; color: #667085; padding: 0 12px 8px;
    border-bottom: 1px solid #E3E8EF;
  }
  table.lk-tbl th.num, table.lk-tbl td.num { text-align: right; }
  table.lk-tbl td { padding: 9px 12px; border-bottom: 1px solid #F1F5F9; }
  table.lk-tbl tr:last-child td { border-bottom: 0; }
  table.lk-tbl tr.tot td { font-weight: 600; border-top: 1px solid #E3E8EF; }
  .lk-arm { display: inline-flex; align-items: center; gap: 9px; white-space: nowrap; }
  .lk-swatch { display: inline-block; width: 9px; height: 9px;
               border-radius: 2px; flex: none; }
  .lk-pre { font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            font-size: 12.5px; line-height: 1.6; color: #101828; margin: 0;
            white-space: pre-wrap; }
  .lk-empty { color: #667085; font-size: 13.5px; margin: 0; }
")

ARM_COLS <- c("#7A8794", "#0072B2", "#D55E00")
FACETS   <- c("Treatment arm" = "ARM", "Sex" = "SEX", "Age group" = "AGEGR1")

ui <- page_sidebar(
  theme = theme,
  title = NULL,
  tags$head(tags$style(css)),

  sidebar = sidebar(
    width = 290,
    open = "open",
    h6("Panel grid", style = "font-weight:650;margin:0 0 2px;"),
    p("Rebuilds the figure server-side.",
      style = "font-size:12.5px;color:#667085;margin:0 0 10px;"),
    selectInput("fcol", "Columns", choices = FACETS, selected = "ARM"),
    # "none" rather than "", because selectize treats an empty option value as
    # a placeholder and drops it, which would make the grid impossible to
    # switch off.
    selectInput("frow", "Rows",
                choices = c("None (single row)" = "none", FACETS),
                selected = "SEX"),
    hr(),
    radioButtons("denom", "Bar length",
                 c("% of arm population" = "population", "Raw count" = "count"),
                 selected = "population"),
    checkboxInput("threads", "Draw threads to bars", TRUE),
    hr(),
    downloadButton("dl", "Download selection (CSV)",
                   class = "btn-sm btn-outline-primary w-100"),
    p(textOutput("dl_note", inline = TRUE),
      style = "font-size:12px;color:#667085;margin:8px 0 0;")
  ),

  div(
    p(class = "lk-eyebrow", "linkagg"),
    h1(class = "lk-title", "Linked selection across a panel grid"),
    p(class = "lk-lede",
      "Drag a box inside any panel. The brush respects both grid dimensions, ",
      "so it selects only subjects in that column and that row. Each bar then ",
      "fills to the share of its own rows the selection covers, and everything ",
      "below is computed in R from ", tags$code("input$fig_selected"), "."),

    linkaggOutput("fig", height = "760px"),

    layout_columns(
      col_widths = c(3, 3, 3, 3),
      style = "margin-top: 22px;",
      card(div(class = "lk-stat", div(class = "lab", "Selected"),
               div(class = "val", textOutput("s_n", inline = TRUE)),
               div(class = "sub", textOutput("s_pct", inline = TRUE)))),
      card(div(class = "lk-stat", div(class = "lab", "Median ALT"),
               div(class = "val", textOutput("s_alt", inline = TRUE)),
               div(class = "sub", "xULN, selected subjects"))),
      card(div(class = "lk-stat", div(class = "lab", "Median TBILI"),
               div(class = "val", textOutput("s_bili", inline = TRUE)),
               div(class = "sub", "xULN, selected subjects"))),
      card(div(class = "lk-stat", div(class = "lab", "Source"),
               div(class = "val", style = "font-size:17px;",
                   textOutput("s_src", inline = TRUE)),
               div(class = "sub", "which panel you brushed")))
    ),

    layout_columns(
      col_widths = c(7, 5),
      style = "margin-top: 22px;",
      card(card_header("Selection by arm and sex"),
           card_body(uiOutput("crosstab"))),
      card(card_header("What R received"),
           card_body(uiOutput("received")))
    )
  )
)

server <- function(input, output, session) {

  # A variable cannot be both axes of the grid. Reset the row rather than
  # rewriting the whole choice list, which would disturb the user's selection
  # every time the column changes.
  observeEvent(input$fcol, {
    if (identical(input$frow, input$fcol)) {
      updateSelectInput(session, "frow", selected = "none")
    }
  })

  facet_row_col <- reactive({
    frow <- input$frow
    if (is.null(frow) || identical(frow, "none") || identical(frow, input$fcol)) {
      NULL
    } else {
      frow
    }
  })

  output$fig <- renderLinkagg({
    spec <- linkagg(adsl, USUBJID, threads = isTRUE(input$threads))

    # The facet columns are chosen at runtime, so they are passed as strings.
    # facet_row is NULL when the grid is switched off, which view_points()
    # reads as "no row variable".
    spec <- view_points(
      spec, TBILI, ALT, log_x = TRUE, log_y = TRUE,
      facet     = input$fcol,
      facet_row = facet_row_col(),
      x_lab = "Peak TBILI (xULN)", y_lab = "Peak ALT (xULN)",
      zone = list(x = 2, y = 3, label = "Hy's law")
    )

    spec |>
      view_bars(SOC, by = ARM, denominator = input$denom) |>
      as_linkagg_widget(height = 760)
  })

  sel_df <- reactive({
    s <- input$fig_selected
    if (is.null(s)) NULL else adsl[adsl$USUBJID %in% s, ]
  })

  fmt1 <- function(v) if (!length(v) || all(is.na(v))) "n/a" else
    format(round(stats::median(v, na.rm = TRUE), 2), nsmall = 2)

  output$s_n    <- renderText(if (is.null(sel_df())) "n/a" else nrow(sel_df()))
  output$s_pct  <- renderText({
    d <- sel_df()
    if (is.null(d)) "no selection active"
    else sprintf("%.1f%% of %d subjects", 100 * nrow(d) / nrow(adsl), nrow(adsl))
  })
  output$s_alt  <- renderText(if (is.null(sel_df())) "n/a" else fmt1(sel_df()$ALT))
  output$s_bili <- renderText(if (is.null(sel_df())) "n/a" else fmt1(sel_df()$TBILI))
  output$s_src  <- renderText(if (is.null(sel_df())) "n/a" else "brushed region")

  output$crosstab <- renderUI({
    d <- sel_df()
    if (is.null(d)) {
      return(p(class = "lk-empty",
               "Nothing selected. Drag a box inside any panel above."))
    }
    arms <- levels(adsl$ARM)
    sexes <- levels(adsl$SEX)
    tab <- table(factor(d$ARM, arms), factor(d$SEX, sexes))
    pop <- table(factor(adsl$ARM, arms))

    tags$table(
      class = "lk-tbl",
      tags$thead(tags$tr(
        tags$th("Arm"),
        lapply(sexes, function(s) tags$th(s, class = "num")),
        tags$th("Total", class = "num"), tags$th("Of arm", class = "num")
      )),
      tags$tbody(
        lapply(seq_along(arms), function(i) {
          rt <- sum(tab[i, ])
          tags$tr(
            tags$td(span(class = "lk-arm",
                         span(class = "lk-swatch",
                              style = paste0("background:", ARM_COLS[i], ";")),
                         arms[i])),
            lapply(seq_along(sexes), function(j) tags$td(tab[i, j], class = "num")),
            tags$td(rt, class = "num"),
            tags$td(sprintf("%.1f%%", 100 * rt / pop[[i]]), class = "num")
          )
        }),
        tags$tr(
          class = "tot",
          tags$td("Total"),
          lapply(seq_along(sexes), function(j) tags$td(sum(tab[, j]), class = "num")),
          tags$td(sum(tab), class = "num"),
          tags$td(sprintf("%.1f%%", 100 * sum(tab) / nrow(adsl)), class = "num")
        )
      )
    )
  })

  output$received <- renderUI({
    s <- input$fig_selected
    if (is.null(s)) {
      return(tags$pre(class = "lk-pre",
                      "input$fig_selected\n  NULL   (no selection active)"))
    }
    tags$pre(class = "lk-pre", paste0(
      "input$fig_selected\n",
      "  class  : ", paste(class(s), collapse = ", "), "\n",
      "  length : ", length(s), "\n\n",
      paste0("  ", utils::head(s, 7), collapse = "\n"),
      if (length(s) > 7) paste0("\n  ... and ", length(s) - 7, " more") else ""
    ))
  })

  output$dl_note <- renderText({
    d <- sel_df()
    if (is.null(d)) "Select subjects to enable a meaningful export."
    else sprintf("%d subjects ready to export.", nrow(d))
  })

  output$dl <- downloadHandler(
    filename = function() {
      sprintf("linkagg-selection-%s.csv", format(Sys.time(), "%Y%m%d-%H%M%S"))
    },
    content = function(file) {
      d <- sel_df()
      if (is.null(d)) d <- adsl[0, ]
      utils::write.csv(d[, c("USUBJID", "ARM", "SEX", "AGEGR1", "ALT", "TBILI")],
                       file, row.names = FALSE)
    }
  )
}

shinyApp(ui, server)
