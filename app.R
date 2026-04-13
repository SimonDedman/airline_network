library(shiny)
library(leaflet)
library(DBI)
library(RSQLite)
library(data.table)

# ---- Load data at startup ----
db_path <- file.path(here::here(), "db", "airline_network.sqlite")
con <- dbConnect(SQLite(), db_path)

airports <- as.data.table(dbGetQuery(con, "
  SELECT iata_code, name, city, country, continent,
         latitude, longitude, type, scheduled_service
  FROM airports
"))

routes <- as.data.table(dbGetQuery(con, "
  SELECT airline_iata, origin_iata, dest_iata, distance_km, flight_min
  FROM routes
"))

airlines <- as.data.table(dbGetQuery(con, "
  SELECT iata_code, name FROM airlines
"))

dbDisconnect(con)

# Drop airports with missing coordinates
airports <- airports[!is.na(latitude) & !is.na(longitude)]
airports[, latitude := as.numeric(latitude)]
airports[, longitude := as.numeric(longitude)]
airports <- airports[!is.na(latitude) & !is.na(longitude)]

# Pre-join airline names to routes
routes <- merge(routes, airlines, by.x = "airline_iata", by.y = "iata_code",
                all.x = TRUE, suffixes = c("", "_airline"))
setnames(routes, "name", "airline_name")

# Build airport labels
airports[, label := paste0(
  "<b>", iata_code, "</b> — ", name,
  "<br>", city, ", ", country
)]

# Colour by type
airports[, colour := fifelse(
  type == "large_airport" & !is.na(type), "#2563eb", "#94a3b8"
)]
airports[, radius := fifelse(
  type == "large_airport" & !is.na(type), 5L, 3L
)]

setkey(routes, origin_iata)

apt_coords <- airports[, .(iata_code, latitude, longitude, city, country, name)]
setkey(apt_coords, iata_code)

# ---- Helper: format flight time ----
fmt_time <- function(mins) {
  fifelse(!is.na(mins),
    paste0("~", mins %/% 60, "h", formatC(mins %% 60, width = 2, flag = "0"), "m"),
    ""
  )
}

# Helper: airport label string
apt_label <- function(code) {
  a <- airports[iata_code == code]
  if (nrow(a) > 0) paste0(a$city[1], " (", code, ")") else code
}


# ---- JS ----
app_js <- HTML('
  // Track Ctrl/Meta key state
  $(document).on("keydown keyup", function(e) {
    Shiny.setInputValue("ctrl_key", e.ctrlKey || e.metaKey, {priority: "event"});
  });

  // Copy report text to clipboard
  Shiny.addCustomMessageHandler("copy_to_clipboard", function(text) {
    navigator.clipboard.writeText(text).then(function() {
      // Flash the button green briefly
      var btn = document.getElementById("copy_report");
      if (btn) {
        btn.style.background = "#22c55e";
        btn.textContent = "Copied!";
        setTimeout(function() {
          btn.style.background = "#7c3aed";
          btn.textContent = "Copy Report";
        }, 1500);
      }
    });
  });
')


# ---- UI ----
ui <- fluidPage(
  tags$head(
    tags$script(app_js),
    tags$style(HTML("
      body { margin: 0; padding: 0; overflow: hidden; }
      .info-bar {
        height: 50px; display: flex; align-items: center;
        padding: 0 16px; background: #1e293b; color: #f8fafc;
        font-family: system-ui, sans-serif; font-size: 14px;
        gap: 12px;
      }
      .info-bar .title { font-weight: 700; font-size: 16px; margin-right: auto; }
      .info-bar .status { color: #94a3b8; }
      .info-bar .hint { color: #64748b; font-size: 12px; }
      .selected-gold { color: #fbbf24; font-weight: 600; }
      .selected-orange { color: #f97316; font-weight: 600; }

      .main-container { display: flex; height: calc(100vh - 50px); }
      .map-pane { flex: 1; min-width: 0; }
      .map-pane .leaflet { height: 100% !important; width: 100% !important; }

      .report-pane {
        width: 380px; background: #0f172a; color: #e2e8f0;
        font-family: 'JetBrains Mono', 'Fira Code', 'Consolas', monospace;
        font-size: 12px; line-height: 1.5;
        display: flex; flex-direction: column;
        border-left: 1px solid #334155;
      }
      .report-header {
        padding: 8px 12px; background: #1e293b;
        display: flex; align-items: center; justify-content: space-between;
        border-bottom: 1px solid #334155; flex-shrink: 0;
      }
      .report-header .label { font-weight: 600; font-size: 13px; }
      .report-body {
        flex: 1; overflow-y: auto; padding: 10px 12px;
        white-space: pre-wrap; word-break: break-word;
      }
      .report-body .section { margin-bottom: 12px; }
      .report-body .via-header {
        color: #a855f7; font-weight: 700; margin-top: 8px;
      }
      .report-body .leg-in { color: #fbbf24; }
      .report-body .leg-out { color: #f97316; }
      .report-body .direct-tag { color: #22c55e; font-weight: 600; }
      .report-body .dim { color: #64748b; }
      .report-body .direct-tag { color: #22c55e; font-weight: 600; }
      .report-body .summary-line { color: #94a3b8; margin-bottom: 6px; }

      #copy_report {
        background: #7c3aed; border: none; color: white;
        padding: 4px 12px; border-radius: 4px; cursor: pointer;
        font-size: 12px; font-weight: 600;
        transition: background 0.2s;
      }
      #copy_report:hover { background: #6d28d9; }
    "))
  ),

  div(class = "info-bar",
    span(class = "title", "Airline Network Explorer"),
    span(class = "status", uiOutput("status_text", inline = TRUE)),
    actionButton("clear", "Clear", class = "btn-sm",
                 style = "background:#475569; border:none; color:#f8fafc; font-size:12px;")
  ),

  div(class = "main-container",
    div(class = "map-pane", leafletOutput("map", height = "100%")),
    div(class = "report-pane",
      div(class = "report-header",
        span(class = "label", "Connection Report"),
        actionButton("copy_report", "Copy Report",
                     style = "background:#7c3aed; border:none; color:white;
                              padding:4px 12px; border-radius:4px; font-size:12px;")
      ),
      div(class = "report-body", uiOutput("report_content"))
    )
  )
)


# ---- Server ----
server <- function(input, output, session) {

  origins      <- reactiveVal(character(0))
  destinations <- reactiveVal(character(0))
  pinnedVia    <- reactiveVal(character(0))
  phase        <- reactiveVal("idle")
  report_text  <- reactiveVal("")  # plain text for clipboard

  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
      addProviderTiles(providers$CartoDB.DarkMatter) |>
      setView(lng = 10, lat = 50, zoom = 4) |>
      addCircleMarkers(
        data = airports,
        lng = ~longitude, lat = ~latitude,
        radius = ~radius,
        color = ~colour,
        fillColor = ~colour,
        fillOpacity = 0.7,
        weight = 1,
        stroke = TRUE,
        opacity = 0.9,
        popup = ~label,
        layerId = ~iata_code,
        group = "airports"
      )
  })

  # ---- Clear all overlays ----
  clear_overlays <- function() {
    leafletProxy("map") |>
      clearGroup("routes") |>
      clearGroup("routes_leg2") |>
      clearGroup("dest_markers") |>
      clearGroup("connections") |>
      clearGroup("origin_highlight") |>
      clearGroup("dest_highlight")
  }

  # ---- Draw direct routes from multiple origins ----
  draw_origin_routes <- function() {
    origs <- origins()
    if (length(origs) == 0) return()

    proxy <- leafletProxy("map")
    origin_routes <- routes[origin_iata %in% origs]
    if (nrow(origin_routes) == 0) return()

    dests <- merge(origin_routes, apt_coords,
                   by.x = "dest_iata", by.y = "iata_code", all.x = TRUE)
    dests <- dests[!is.na(latitude)]

    for (o_code in origs) {
      orig <- airports[iata_code == o_code]
      if (nrow(orig) == 0) next
      proxy |> addCircleMarkers(
        lng = orig$longitude[1], lat = orig$latitude[1], radius = 8,
        color = "#fbbf24", fillColor = "#fbbf24",
        fillOpacity = 1, weight = 2, stroke = TRUE,
        group = "origin_highlight"
      )
    }

    for (o_code in origs) {
      orig <- airports[iata_code == o_code]
      if (nrow(orig) == 0) next
      o_lat <- orig$latitude[1]; o_lng <- orig$longitude[1]
      o_dests <- dests[origin_iata == o_code]
      o_dests_unique <- o_dests[!duplicated(dest_iata)]
      for (i in seq_len(nrow(o_dests_unique))) {
        proxy |> addPolylines(
          lng = c(o_lng, o_dests_unique$longitude[i]),
          lat = c(o_lat, o_dests_unique$latitude[i]),
          color = "#fbbf24", weight = 1.2, opacity = 0.35,
          group = "routes"
        )
      }
    }

    dest_summary <- dests[, .(
      airlines = paste(unique(paste0(airline_name, " (", airline_iata, ")")),
                       collapse = "<br>"),
      from_origins = paste(unique(origin_iata), collapse = ", "),
      latitude = latitude[1], longitude = longitude[1],
      name = name[1], city = city[1], country = country[1],
      distance_km = min(distance_km, na.rm = TRUE),
      flight_min = min(flight_min, na.rm = TRUE)
    ), by = dest_iata]
    dest_summary <- dest_summary[!dest_iata %in% origs]

    dest_summary[, popup := paste0(
      "<b>", dest_iata, "</b> — ", name,
      "<br>", city, ", ", country,
      "<br>", distance_km, " km",
      fifelse(is.finite(flight_min), paste0(" · ", fmt_time(flight_min)), ""),
      "<br>From: ", from_origins,
      "<br><hr style='margin:4px 0'>", airlines
    )]

    proxy |> addCircleMarkers(
      data = dest_summary,
      lng = ~longitude, lat = ~latitude, radius = 5,
      color = "#f97316", fillColor = "#f97316",
      fillOpacity = 0.8, weight = 1, stroke = TRUE,
      popup = ~popup, layerId = ~paste0("dest_", dest_iata),
      group = "dest_markers"
    )
  }

  # ---- Draw connections ----
  draw_connections <- function() {
    origs <- origins()
    dests_selected <- destinations()
    if (length(origs) == 0 || length(dests_selected) == 0) return()

    proxy <- leafletProxy("map")

    from_origins <- unique(routes[origin_iata %in% origs, dest_iata])
    to_dests <- unique(routes[dest_iata %in% dests_selected, origin_iata])
    via_airports <- setdiff(intersect(from_origins, to_dests),
                            c(origs, dests_selected))

    for (o_code in origs) {
      orig <- airports[iata_code == o_code]
      if (nrow(orig) == 0) next
      proxy |> addCircleMarkers(
        lng = orig$longitude[1], lat = orig$latitude[1], radius = 9,
        color = "#fbbf24", fillColor = "#fbbf24",
        fillOpacity = 1, weight = 2, stroke = TRUE,
        group = "origin_highlight"
      )
    }

    for (d_code in dests_selected) {
      dest <- airports[iata_code == d_code]
      if (nrow(dest) == 0) next
      proxy |> addCircleMarkers(
        lng = dest$longitude[1], lat = dest$latitude[1], radius = 9,
        color = "#f97316", fillColor = "#f97316",
        fillOpacity = 1, weight = 2, stroke = TRUE,
        group = "dest_highlight"
      )
    }

    if (length(via_airports) == 0) return()

    via_dt <- apt_coords[iata_code %in% via_airports]
    if (nrow(via_dt) == 0) return()

    for (i in seq_len(nrow(via_dt))) {
      v <- via_dt[i]
      leg1_routes <- routes[origin_iata %in% origs & dest_iata == v$iata_code]
      leg2_routes <- routes[origin_iata == v$iata_code & dest_iata %in% dests_selected]

      for (o_code in unique(leg1_routes$origin_iata)) {
        orig <- airports[iata_code == o_code]
        if (nrow(orig) == 0) next
        proxy |> addPolylines(
          lng = c(orig$longitude[1], v$longitude),
          lat = c(orig$latitude[1], v$latitude),
          color = "#fbbf24", weight = 1.5, opacity = 0.4,
          group = "routes"
        )
      }

      for (d_code in unique(leg2_routes$dest_iata)) {
        dest <- airports[iata_code == d_code]
        if (nrow(dest) == 0) next
        proxy |> addPolylines(
          lng = c(v$longitude, dest$longitude[1]),
          lat = c(v$latitude, dest$latitude[1]),
          color = "#f97316", weight = 1.5, opacity = 0.4,
          group = "routes_leg2"
        )
      }

      leg1_txt <- leg1_routes[, paste(
        unique(paste0(origin_iata, ": ", airline_name, " (", airline_iata, ")")),
        collapse = "<br>"
      )]
      leg2_txt <- leg2_routes[, paste(
        unique(paste0("\u2192 ", dest_iata, ": ", airline_name, " (", airline_iata, ")")),
        collapse = "<br>"
      )]

      popup_html <- paste0(
        "<b>Via ", v$iata_code, "</b> \u2014 ", v$name,
        "<br>", v$city, ", ", v$country,
        "<br><hr style='margin:4px 0'>",
        "<b>Inbound:</b><br>", leg1_txt,
        "<br><br><b>Onward:</b><br>", leg2_txt
      )

      is_pinned <- v$iata_code %in% pinnedVia()
      proxy |> addCircleMarkers(
        lng = v$longitude, lat = v$latitude,
        radius = if (is_pinned) 8 else 6,
        color = if (is_pinned) "#c084fc" else "#a855f7",
        fillColor = if (is_pinned) "#c084fc" else "#a855f7",
        fillOpacity = 0.9, weight = if (is_pinned) 2 else 1, stroke = TRUE,
        popup = popup_html,
        layerId = paste0("via_", v$iata_code),
        group = "connections"
      )
    }
  }

  # ---- Build report data ----
  build_report <- function() {
    origs <- origins()
    dests_selected <- destinations()
    cur_phase <- phase()

    if (cur_phase == "idle") {
      report_text("")
      return(list(html = tags$span(class = "dim", "Select airports to generate a report."),
                  text = ""))
    }

    if (cur_phase == "origins") {
      # Origin-mode report: list destinations grouped by country
      o_labels <- vapply(origs, apt_label, character(1))
      origin_routes <- routes[origin_iata %in% origs]
      if (nrow(origin_routes) == 0) {
        txt <- paste0("Origins: ", paste(o_labels, collapse = " + "), "\nNo routes found.")
        report_text(txt)
        return(list(html = tags$span(class = "dim", "No routes found."), text = txt))
      }

      dest_info <- merge(origin_routes, apt_coords[, .(iata_code, city, country)],
                         by.x = "dest_iata", by.y = "iata_code", all.x = TRUE)
      dest_info <- dest_info[!dest_iata %in% origs]

      # Aggregate per destination
      dest_agg <- dest_info[, .(
        airlines = paste(sort(unique(paste0(airline_name, " (", airline_iata, ")"))),
                         collapse = ", "),
        from = paste(sort(unique(origin_iata)), collapse = "/"),
        city = city[1], country = country[1],
        km = min(distance_km, na.rm = TRUE),
        mins = min(flight_min, na.rm = TRUE)
      ), by = dest_iata]
      setorder(dest_agg, country, city)

      # Build text
      lines <- c(
        paste0("DESTINATIONS FROM: ", paste(o_labels, collapse = " + ")),
        paste0(nrow(dest_agg), " destinations"),
        paste0(rep("\u2500", 50), collapse = "")
      )

      for (cty in unique(dest_agg$country)) {
        lines <- c(lines, "", paste0("\u25B8 ", cty))
        rows <- dest_agg[country == cty]
        for (j in seq_len(nrow(rows))) {
          r <- rows[j]
          time_str <- if (is.finite(r$mins)) {
            paste0(" ", r$mins %/% 60, "h", formatC(r$mins %% 60, width = 2, flag = "0"), "m")
          } else ""
          lines <- c(lines, paste0(
            "  ", r$dest_iata, " ", r$city,
            " (", r$km, "km", time_str, ")",
            " [", r$airlines, "]"
          ))
        }
      }

      txt <- paste(lines, collapse = "\n")
      report_text(txt)

      # HTML version
      html_parts <- list(
        tags$div(class = "summary-line",
          paste0("Destinations from: ", paste(o_labels, collapse = " + ")),
          tags$br(), paste0(nrow(dest_agg), " destinations")
        )
      )

      for (cty in unique(dest_agg$country)) {
        rows <- dest_agg[country == cty]
        country_lines <- lapply(seq_len(nrow(rows)), function(j) {
          r <- rows[j]
          time_str <- if (is.finite(r$mins)) {
            paste0(" ", r$mins %/% 60, "h", formatC(r$mins %% 60, width = 2, flag = "0"), "m")
          } else ""
          tags$div(paste0(
            "  ", r$dest_iata, " ", r$city,
            " (", r$km, "km", time_str, ") ",
            "[", r$airlines, "]"
          ))
        })
        html_parts <- c(html_parts, list(
          tags$div(class = "via-header", paste0("\u25B8 ", cty)),
          country_lines
        ))
      }

      return(list(html = tagList(html_parts), text = txt))
    }

    # ---- Connection mode report ----
    o_labels <- vapply(origs, apt_label, character(1))
    d_labels <- vapply(dests_selected, apt_label, character(1))

    from_origins <- unique(routes[origin_iata %in% origs, dest_iata])
    to_dests <- unique(routes[dest_iata %in% dests_selected, origin_iata])
    via_airports <- setdiff(intersect(from_origins, to_dests),
                            c(origs, dests_selected))

    # Check direct routes
    direct_routes <- routes[origin_iata %in% origs & dest_iata %in% dests_selected]

    lines <- c(
      paste0("CONNECTIONS: ", paste(o_labels, collapse = " + "),
             " \u2192 ", paste(d_labels, collapse = " + ")),
      paste0(length(via_airports), " connecting airports",
             if (nrow(direct_routes) > 0) " (+ direct)" else ""),
      paste0(rep("\u2500", 50), collapse = "")
    )

    html_parts <- list(
      tags$div(class = "summary-line",
        tags$span(class = "selected-gold", paste(o_labels, collapse = " + ")),
        " \u2192 ",
        tags$span(class = "selected-orange", paste(d_labels, collapse = " + ")),
        tags$br(),
        paste0(length(via_airports), " connecting airports",
               if (nrow(direct_routes) > 0) " (+ direct)" else "")
      )
    )

    # Direct routes section
    if (nrow(direct_routes) > 0) {
      lines <- c(lines, "", "\u2605 DIRECT FLIGHTS")
      html_parts <- c(html_parts, list(
        tags$div(class = "direct-tag", "\u2605 DIRECT FLIGHTS")
      ))
      direct_agg <- direct_routes[, .(
        airlines = paste(sort(unique(paste0(airline_name, " (", airline_iata, ")"))),
                         collapse = ", "),
        km = distance_km[1],
        mins = flight_min[1]
      ), by = .(origin_iata, dest_iata)]
      for (j in seq_len(nrow(direct_agg))) {
        r <- direct_agg[j]
        time_str <- if (!is.na(r$mins)) {
          paste0(" ", r$mins %/% 60, "h", formatC(r$mins %% 60, width = 2, flag = "0"), "m")
        } else ""
        line <- paste0("  ", r$origin_iata, " \u2192 ", r$dest_iata,
                        " (", r$km, "km", time_str, ") [", r$airlines, "]")
        lines <- c(lines, line)
        html_parts <- c(html_parts, list(tags$div(line)))
      }
    }

    # Helper: build detail lines/html for one via airport
    via_detail <- function(v) {
      dl <- character(0); dh <- list()
      leg1 <- routes[origin_iata %in% origs & dest_iata == v$iata_code]
      leg2 <- routes[origin_iata == v$iata_code & dest_iata %in% dests_selected]

      leg1_agg <- leg1[, .(
        airlines = paste(sort(unique(paste0(airline_name, " (", airline_iata, ")"))),
                         collapse = ", "),
        km = distance_km[1], mins = flight_min[1]
      ), by = origin_iata]
      for (j in seq_len(nrow(leg1_agg))) {
        r <- leg1_agg[j]
        ts <- if (!is.na(r$mins)) paste0(" ", r$mins %/% 60, "h",
              formatC(r$mins %% 60, width = 2, flag = "0"), "m") else ""
        ln <- paste0("    \u2190 ", r$origin_iata, " (", r$km, "km", ts, ") ", r$airlines)
        dl <- c(dl, ln)
        dh <- c(dh, list(tags$div(class = "leg-in", ln)))
      }

      leg2_agg <- leg2[, .(
        airlines = paste(sort(unique(paste0(airline_name, " (", airline_iata, ")"))),
                         collapse = ", "),
        km = distance_km[1], mins = flight_min[1]
      ), by = dest_iata]
      for (j in seq_len(nrow(leg2_agg))) {
        r <- leg2_agg[j]
        ts <- if (!is.na(r$mins)) paste0(" ", r$mins %/% 60, "h",
              formatC(r$mins %% 60, width = 2, flag = "0"), "m") else ""
        ln <- paste0("    \u2192 ", r$dest_iata, " (", r$km, "km", ts, ") ", r$airlines)
        dl <- c(dl, ln)
        dh <- c(dh, list(tags$div(class = "leg-out", ln)))
      }
      list(lines = dl, html = dh)
    }

    # Via airports
    if (length(via_airports) > 0) {
      via_dt <- apt_coords[iata_code %in% via_airports]
      setorder(via_dt, country, city)
      pinned <- pinnedVia()

      # Pinned connections (expanded, at top)
      pinned_dt <- via_dt[iata_code %in% pinned]
      if (nrow(pinned_dt) > 0) {
        lines <- c(lines, "", "\U0001F4CD PINNED CONNECTIONS")
        html_parts <- c(html_parts, list(
          tags$div(style = "margin-top:8px; font-weight:700; color:#c084fc;",
                   "\U0001F4CD PINNED CONNECTIONS")
        ))
        for (i in seq_len(nrow(pinned_dt))) {
          v <- pinned_dt[i]
          hdr <- paste0("  ", v$iata_code, " \u2014 ", v$name, " (", v$city, ", ", v$country, ")")
          lines <- c(lines, hdr)
          html_parts <- c(html_parts, list(
            tags$div(style = "color:#c084fc; font-weight:600; margin-top:4px;", hdr)
          ))
          detail <- via_detail(v)
          lines <- c(lines, detail$lines)
          html_parts <- c(html_parts, detail$html)
        }
      }

      # All connections grouped by country
      lines <- c(lines, "", "CONNECTING AIRPORTS")
      html_parts <- c(html_parts, list(
        tags$div(style = "margin-top:8px; font-weight:700;", "CONNECTING AIRPORTS")
      ))

      current_country <- ""
      for (i in seq_len(nrow(via_dt))) {
        v <- via_dt[i]
        is_pinned <- v$iata_code %in% pinned

        if (v$country != current_country) {
          current_country <- v$country
          lines <- c(lines, "", paste0("\u25B8 ", current_country))
          html_parts <- c(html_parts, list(
            tags$div(class = "via-header", paste0("\u25B8 ", current_country))
          ))
        }

        pin_mark <- if (is_pinned) " \U0001F4CD" else ""
        via_line <- paste0("  ", v$iata_code, " ", v$city, pin_mark)
        lines <- c(lines, via_line)
        html_parts <- c(html_parts, list(
          tags$div(style = paste0("color:#a855f7; font-weight:600; margin-top:4px;",
                                  if (is_pinned) " border-left:2px solid #a855f7; padding-left:4px;" else ""),
                   via_line)
        ))

        # Show detail inline for pinned items
        if (is_pinned) {
          detail <- via_detail(v)
          lines <- c(lines, detail$lines)
          html_parts <- c(html_parts, detail$html)
        }
      }
    }

    txt <- paste(lines, collapse = "\n")
    report_text(txt)
    list(html = tagList(html_parts), text = txt)
  }

  # ---- Redraw ----
  redraw <- function() {
    clear_overlays()
    if (phase() == "origins") {
      draw_origin_routes()
    } else if (phase() == "destinations") {
      draw_connections()
    }
  }

  toggle <- function(vec, item) {
    if (item %in% vec) setdiff(vec, item) else c(vec, item)
  }

  # ---- Handle airport click ----
  observeEvent(input$map_marker_click, {
    click <- input$map_marker_click
    if (is.null(click$id)) return()

    click_id <- click$id

    # Detect via-airport click (for pinning)
    is_via_click <- startsWith(click_id, "via_")
    if (is_via_click) {
      via_code <- sub("^via_", "", click_id)
      pinnedVia(toggle(pinnedVia(), via_code))
      redraw()  # redraw to update marker styling
      return()
    }

    if (startsWith(click_id, "dest_")) {
      click_id <- sub("^dest_", "", click_id)
    }

    ctrl <- isTRUE(input$ctrl_key)
    cur_phase <- phase()

    if (cur_phase == "idle") {
      origins(click_id)
      destinations(character(0))
      pinnedVia(character(0))
      phase("origins")
      redraw()

    } else if (cur_phase == "origins") {
      if (ctrl) {
        new_origs <- toggle(origins(), click_id)
        if (length(new_origs) == 0) {
          origins(character(0))
          phase("idle")
          clear_overlays()
        } else {
          origins(new_origs)
          redraw()
        }
      } else {
        if (click_id %in% origins()) {
          origins(click_id)
          destinations(character(0))
          redraw()
        } else {
          destinations(click_id)
          phase("destinations")
          redraw()
        }
      }

    } else if (cur_phase == "destinations") {
      if (ctrl) {
        if (click_id %in% origins()) {
          new_origs <- setdiff(origins(), click_id)
          if (length(new_origs) == 0) {
            origins(character(0)); destinations(character(0))
            phase("idle"); clear_overlays()
          } else {
            origins(new_origs); redraw()
          }
        } else {
          new_dests <- toggle(destinations(), click_id)
          if (length(new_dests) == 0) {
            destinations(character(0))
            phase("origins")
            redraw()
          } else {
            destinations(new_dests); redraw()
          }
        }
      } else {
        origins(click_id)
        destinations(character(0))
        phase("origins")
        redraw()
      }
    }
  })

  # ---- Copy button ----
  observeEvent(input$copy_report, {
    session$sendCustomMessage("copy_to_clipboard", report_text())
  })

  # ---- Clear button ----
  observeEvent(input$clear, {
    origins(character(0))
    destinations(character(0))
    pinnedVia(character(0))
    phase("idle")
    clear_overlays()
  })

  # ---- Report panel ----
  output$report_content <- renderUI({
    # Trigger on any state change
    origins(); destinations(); phase()
    report <- build_report()
    report$html
  })

  # ---- Status text ----
  output$status_text <- renderUI({
    origs <- origins()
    dests_sel <- destinations()
    cur_phase <- phase()

    if (cur_phase == "idle") {
      tags$span(
        paste0(nrow(airports), " airports, ",
               format(nrow(routes), big.mark = ","), " routes"),
        tags$span(class = "hint", " · Click airport · Ctrl+click to multi-select")
      )
    } else if (cur_phase == "origins") {
      o_labels <- vapply(origs, apt_label, character(1))
      n_dest <- uniqueN(routes[origin_iata %in% origs, dest_iata])
      tagList(
        tags$span(class = "selected-gold", paste(o_labels, collapse = " + ")),
        paste0(" \u2014 ", n_dest, " destinations"),
        tags$span(class = "hint", " · Ctrl+click: +/- origin · Click dest for connections")
      )
    } else {
      o_labels <- vapply(origs, apt_label, character(1))
      d_labels <- vapply(dests_sel, apt_label, character(1))
      from_origins <- unique(routes[origin_iata %in% origs, dest_iata])
      to_dests <- unique(routes[dest_iata %in% dests_sel, origin_iata])
      n_via <- length(setdiff(intersect(from_origins, to_dests), c(origs, dests_sel)))
      has_direct <- nrow(routes[origin_iata %in% origs & dest_iata %in% dests_sel]) > 0
      direct_txt <- if (has_direct) " (+ direct)" else ""
      tagList(
        tags$span(class = "selected-gold", paste(o_labels, collapse = " + ")),
        " \u2192 ",
        tags$span(class = "selected-orange", paste(d_labels, collapse = " + ")),
        paste0(" \u2014 ", n_via, " connecting", direct_txt),
        tags$span(class = "hint", " · Ctrl+click: +/- · Click to restart")
      )
    }
  })
}

shinyApp(ui, server)
