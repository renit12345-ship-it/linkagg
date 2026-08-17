# linkagg inside Shiny.
#
# The point of this app is the round trip: brushing the scatter sends the
# selected keys back to R as input$fig_selected, and everything below the
# figure is computed in R from that vector. Launch it with
# linkagg::run_linkagg_app().

if (!"linkagg" %in% loadedNamespaces()) library(linkagg)
library(shiny)
library(bslib)

set.seed(42)
n <- 240
socs <- c("Hepatobiliary disorders", "Investigations",
          "Gastrointestinal disorders", "Skin and subcutaneous tissue disorders")

adsl <- data.frame(
  USUBJID = sprintf("01-%03d", seq_len(n)),
  ARM     = factor(rep(c("Placebo", "Drug A 50mg", "Drug A 100mg"), each = n / 3),
                   levels = c("Placebo", "Drug A 50mg", "Drug A 100mg")),
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
  version    = 5,
  bg         = "#FFFFFF",
  fg         = "#101828",
  primary    = "#1D4ED8",
  base_font  = SANS,
  heading_font = SANS,
  "body-bg"  = "#F8FAFC",
  "border-color" = "#E3E8EF",
  "card-border-radius" = "12px",
  "card-cap-bg" = "#FFFFFF"
)

css <- HTML("
  body { font-variant-numeric: tabular-nums; }
  .lk-wrap { max-width: 1180px; margin: 0 auto; padding: 36px 24px 56px; }
  .lk-eyebrow {
    font-size: 11px; font-weight: 600; letter-spacing: .08em;
    text-transform: uppercase; color: #667085; margin: 0 0 6px;
  }
  .lk-title {
    font-size: 27px; font-weight: 650; letter-spacing: -.02em;
    color: #101828; margin: 0 0 8px;
  }
  .lk-lede {
    font-size: 15px; line-height: 1.6; color: #475467;
    max-width: 66ch; margin: 0 0 28px;
  }
  .lk-lede code {
    background: #F1F5F9; color: #1D4ED8; padding: 1px 6px;
    border-radius: 5px; font-size: 13px;
  }
  .card { box-shadow: 0 1px 2px rgba(16,24,40,.05); }
  .card-header {
    font-size: 12px; font-weight: 600; letter-spacing: .05em;
    text-transform: uppercase; color: #667085;
    border-bottom: 1px solid #E3E8EF; padding: 12px 18px;
  }
  .lk-pre {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 12.5px; line-height: 1.65; color: #101828;
    background: #F8FAFC; border: 1px solid #E3E8EF; border-radius: 8px;
    padding: 14px 16px; margin: 0; white-space: pre-wrap;
  }
  table.lk-tbl { width: 100%; border-collapse: collapse; font-size: 13.5px; }
  table.lk-tbl th {
    text-align: left; font-size: 10.5px; font-weight: 600;
    letter-spacing: .06em; text-transform: uppercase; color: #667085;
    padding: 0 12px 8px; border-bottom: 1px solid #E3E8EF;
  }
  table.lk-tbl td {
    padding: 9px 12px; border-bottom: 1px solid #F1F5F9; color: #101828;
  }
  table.lk-tbl td.num { text-align: right; }
  table.lk-tbl tr:last-child td { border-bottom: 0; }
  .lk-arm { display: inline-flex; align-items: center; gap: 9px; white-space: nowrap; }
  .lk-swatch {
    display: inline-block; width: 9px; height: 9px; border-radius: 2px;
    flex: none;
  }
  .lk-foot { font-size: 12.5px; color: #667085; margin-top: 28px; }
")

# Matches the widget's own arm colours, so the table below reads as one figure.
ARM_COLS <- c("#7A8794", "#0072B2", "#D55E00")

ui <- page_fluid(
  theme = theme,
  tags$head(tags$style(css)),
  div(
    class = "lk-wrap",
    p(class = "lk-eyebrow", "linkagg"),
    h1(class = "lk-title", "Linked selection across aggregate views"),
    p(class = "lk-lede",
      "Drag a box on the scatter. Each bar fills to the share of its own rows ",
      "that fall inside the selection. Everything below the figure is computed ",
      "in R from ", tags$code("input$fig_selected"), ", so the selection really ",
      "does cross back out of the browser."),

    # The figure carries its own card treatment, so it sits directly on the page.
    linkaggOutput("fig", height = "800px"),

    layout_columns(
      col_widths = c(5, 7),
      style = "margin-top: 28px;",
      card(
        card_header("What R received"),
        card_body(verbatimTextOutput("received"))
      ),
      card(
        card_header("Selected subjects by arm"),
        card_body(uiOutput("by_arm"))
      )
    ),
    p(class = "lk-foot",
      "Simulated data, 240 subjects. Arm colours are Okabe-Ito derived and ",
      "remain distinguishable under the common forms of colour blindness.")
  )
)

server <- function(input, output, session) {

  output$fig <- renderLinkagg({
    linkagg(adsl, USUBJID) |>
      view_points(TBILI, ALT, log_x = TRUE, log_y = TRUE,
                  x_lab = "Peak TBILI (xULN)", y_lab = "Peak ALT (xULN)",
                  zone = list(x = 2, y = 3, label = "Hy's law")) |>
      view_bars(SOC, by = ARM) |>
      view_table(cols = c("USUBJID", "ARM", "ALT", "TBILI")) |>
      as_linkagg_widget(height = 800)
  })

  # NULL when nothing is selected, otherwise a character vector of USUBJID.
  selected <- reactive(input$fig_selected)

  output$received <- renderPrint({
    s <- selected()
    if (is.null(s)) {
      cat("input$fig_selected\n  NULL  (no selection active)\n")
    } else {
      cat("input$fig_selected\n")
      cat("  class  :", class(s), "\n")
      cat("  length :", length(s), "\n\n")
      cat(paste0("  ", utils::head(s, 6)), sep = "\n")
      if (length(s) > 6) cat("\n  ... and", length(s) - 6, "more\n")
    }
  })

  output$by_arm <- renderUI({
    s <- selected()
    lv <- levels(adsl$ARM)
    if (is.null(s)) {
      return(p(style = "color:#667085;font-size:13.5px;margin:0;",
               "Nothing selected yet. Brush the scatter above."))
    }
    sub <- adsl[adsl$USUBJID %in% s, ]
    sel <- as.integer(table(sub$ARM)[lv])
    pop <- as.integer(table(adsl$ARM)[lv])
    med <- round(tapply(sub$ALT, sub$ARM, median)[lv], 2)

    tags$table(
      class = "lk-tbl",
      tags$thead(tags$tr(
        tags$th("Arm"), tags$th("Selected", class = "num"),
        tags$th("Population", class = "num"), tags$th("Share", class = "num"),
        tags$th("Median ALT", class = "num")
      )),
      tags$tbody(lapply(seq_along(lv), function(i) {
        tags$tr(
          tags$td(span(
            class = "lk-arm",
            span(class = "lk-swatch",
                 style = paste0("background:", ARM_COLS[i], ";")), lv[i])),
          tags$td(sel[i], class = "num"),
          tags$td(pop[i], class = "num"),
          tags$td(sprintf("%.1f%%", 100 * sel[i] / pop[i]), class = "num"),
          tags$td(ifelse(is.na(med[i]), "—", format(med[i])), class = "num")
        )
      }))
    )
  })
}

shinyApp(ui, server)
