# linkagg inside Shiny.
#
# The point of this app is the round trip: brushing the scatter sends the
# selected keys back to R as input$fig_selected, and everything below the
# figure is computed in R from that vector. Launch it with
# linkagg::run_linkagg_app().

if (!"linkagg" %in% loadedNamespaces()) library(linkagg)
library(shiny)

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

ui <- fluidPage(
  titlePanel("linkagg in Shiny"),
  p("Drag a box on the scatter. The panel below is computed in R from",
    code("input$fig_selected"), "- proof the selection crosses back."),
  # Keep this height matched to as_linkagg_widget(height = ) below, or the
  # figure overlaps whatever follows it.
  linkaggOutput("fig", height = "800px"),
  hr(),
  fluidRow(
    column(4, h4("What R received"), verbatimTextOutput("received")),
    column(8, h4("Selected subjects by arm"), tableOutput("by_arm"))
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
      cat("input$fig_selected is NULL\n(no selection active)\n")
    } else {
      cat("length:", length(s), "\n")
      cat("class :", class(s), "\n\n")
      cat(utils::head(s, 8), sep = "\n")
      if (length(s) > 8) cat("\n... and", length(s) - 8, "more\n")
    }
  })

  output$by_arm <- renderTable({
    s <- selected()
    if (is.null(s)) return(NULL)
    sub <- adsl[adsl$USUBJID %in% s, ]
    data.frame(
      Arm        = levels(adsl$ARM),
      Selected   = as.integer(table(sub$ARM)[levels(adsl$ARM)]),
      Population = as.integer(table(adsl$ARM)[levels(adsl$ARM)]),
      `Median ALT` = round(tapply(sub$ALT, sub$ARM, median)[levels(adsl$ARM)], 2),
      check.names = FALSE
    )
  })
}

shinyApp(ui, server)
