# 04_ingest_jonty.R
# Ingest current route data from Jonty/airline-route-data (GitHub)
# https://github.com/Jonty/airline-route-data
#
# This replaces stale OpenFlights routes (~2014) with weekly-updated data.
# Run after 01_download_data.R and 02_build_database.R, or standalone
# to refresh the routes table.

library(data.table)
library(jsonlite)
library(DBI)
library(RSQLite)

data_dir <- file.path(here::here(), "data")
db_path  <- file.path(here::here(), "db", "airline_network.sqlite")

json_path <- file.path(data_dir, "jonty_airline_routes.json")

# ---- Download if missing or stale (>7 days) ----
needs_download <- !file.exists(json_path) ||
  difftime(Sys.time(), file.mtime(json_path), units = "days") > 7

if (needs_download) {
  cat("Downloading current route data from Jonty/airline-route-data...\n")
  curl::curl_download(
    "https://raw.githubusercontent.com/Jonty/airline-route-data/refs/heads/main/airline_routes.json",
    json_path
  )
  cat("Downloaded:", format(file.size(json_path) / 1e6, digits = 1), "MB\n")
} else {
  cat("Using cached route data from",
      format(file.mtime(json_path), "%Y-%m-%d"), "\n")
}

# ---- Parse JSON ----
cat("Parsing JSON...\n")
raw <- fromJSON(json_path, simplifyVector = FALSE)
cat("Airports in source:", length(raw), "\n")

# ---- Extract airports ----
cat("Extracting airports...\n")
airports_list <- lapply(raw, function(a) {
  data.table(
    iata_code   = a$iata %||% NA_character_,
    icao_code   = a$icao %||% NA_character_,
    name        = a$name %||% NA_character_,
    city        = a$city_name %||% NA_character_,
    country     = a$country %||% NA_character_,
    iso_country = a$country_code %||% NA_character_,
    continent   = a$continent %||% NA_character_,
    latitude    = a$latitude %||% NA_real_,
    longitude   = a$longitude %||% NA_real_,
    elevation_ft = a$elevation %||% NA_integer_,
    timezone    = a$timezone %||% NA_character_
  )
})
airports_jonty <- rbindlist(airports_list)
airports_jonty <- airports_jonty[!is.na(iata_code) & iata_code != ""]

# ---- Extract routes ----
cat("Extracting routes...\n")
routes_list <- list()
for (a in raw) {
  origin <- a$iata
  if (is.null(origin) || origin == "") next
  for (r in a$routes) {
    dest <- r$iata
    if (is.null(dest) || dest == "") next
    # Each route may have multiple carriers
    for (carrier in r$carriers) {
      routes_list[[length(routes_list) + 1L]] <- data.table(
        airline_iata = carrier$iata %||% NA_character_,
        airline_name = carrier$name %||% NA_character_,
        origin_iata  = origin,
        dest_iata    = dest,
        distance_km  = r$km %||% NA_integer_,
        flight_min   = r$min %||% NA_integer_,
        source       = "jonty"
      )
    }
  }
}
routes_jonty <- rbindlist(routes_list)
cat("Route-carrier pairs extracted:", nrow(routes_jonty), "\n")

# ---- Build/update database ----
cat("Writing to database...\n")
con <- dbConnect(SQLite(), db_path)

# Drop old tables and recreate
dbExecute(con, "DROP TABLE IF EXISTS routes")
dbExecute(con, "DROP TABLE IF EXISTS airlines")
dbExecute(con, "DROP TABLE IF EXISTS airports")
dbExecute(con, "DROP VIEW IF EXISTS europe_airports")
dbExecute(con, "DROP VIEW IF EXISTS europe_routes")

# Airports: merge Jonty data with OurAirports for completeness
# Jonty has better coverage of active airports; OurAirports has more metadata
oa_path <- file.path(data_dir, "ourairports_airports.csv")
if (file.exists(oa_path)) {
  cat("Merging with OurAirports for additional airports...\n")
  oa <- fread(oa_path, na.strings = "")
  oa <- oa[type %in% c("large_airport", "medium_airport") &
             !is.na(iata_code) & iata_code != ""]

  # OurAirports fields we want
  oa_airports <- oa[, .(
    iata_code    = iata_code,
    icao_code    = ident,
    name         = name,
    city         = municipality,
    iso_country  = iso_country,
    iso_region   = iso_region,
    latitude     = latitude_deg,
    longitude    = longitude_deg,
    elevation_ft = elevation_ft,
    type         = type,
    scheduled_service = scheduled_service
  )]

  # Add country/continent/region from OurAirports reference files
  countries_path <- file.path(data_dir, "ourairports_countries.csv")
  regions_path   <- file.path(data_dir, "ourairports_regions.csv")
  if (file.exists(countries_path)) {
    countries <- fread(countries_path, na.strings = "")
    oa_airports <- merge(oa_airports,
      countries[, .(iso_country = code, country = name, continent)],
      by = "iso_country", all.x = TRUE)
  }
  if (file.exists(regions_path)) {
    regions <- fread(regions_path, na.strings = "")
    oa_airports <- merge(oa_airports,
      regions[, .(iso_region = code, region = name)],
      by = "iso_region", all.x = TRUE)
  }

  # Prefer Jonty for airports it knows about (they're confirmed active),
  # fill in OurAirports extras
  # Standardise continent codes: Jonty uses full names, OurAirports uses 2-letter
  continent_map <- c(
    "Africa" = "AF", "Antarctica" = "AN", "Asia" = "AS",
    "Europe" = "EU", "North America" = "NA", "Oceania" = "OC",
    "South America" = "SA"
  )
  airports_jonty[, continent := continent_map[continent]]

  # Use OurAirports as base, update with Jonty where available
  # This gives us OurAirports' richer metadata + Jonty's coverage confirmation
  airports_final <- copy(oa_airports)

  # Add any Jonty airports not in OurAirports
  missing <- airports_jonty[!iata_code %in% airports_final$iata_code]
  if (nrow(missing) > 0) {
    # Pad missing columns
    for (col in setdiff(names(airports_final), names(missing))) {
      missing[, (col) := NA]
    }
    missing <- missing[, names(airports_final), with = FALSE]
    airports_final <- rbindlist(list(airports_final, missing), fill = TRUE)
  }

  # Deduplicate
  airports_final <- airports_final[!duplicated(iata_code)]
} else {
  # No OurAirports data, use Jonty only
  airports_final <- airports_jonty
}

dbWriteTable(con, "airports", airports_final, overwrite = TRUE)
cat("  Airports:", nrow(airports_final), "\n")

# Airlines: extract unique from routes
airlines_jonty <- unique(routes_jonty[
  !is.na(airline_iata) & airline_iata != "",
  .(iata_code = airline_iata, name = airline_name)
])
airlines_jonty <- airlines_jonty[!duplicated(iata_code)]

dbWriteTable(con, "airlines", airlines_jonty, overwrite = TRUE)
cat("  Airlines:", nrow(airlines_jonty), "\n")

# Routes
routes_final <- routes_jonty[, .(
  airline_iata, origin_iata, dest_iata,
  distance_km, flight_min, source
)]

dbWriteTable(con, "routes", routes_final, overwrite = TRUE)
cat("  Routes:", nrow(routes_final), "\n")

# ---- Indexes ----
dbExecute(con, "CREATE INDEX idx_airports_iata ON airports(iata_code)")
dbExecute(con, "CREATE INDEX idx_airports_country ON airports(iso_country)")
dbExecute(con, "CREATE INDEX idx_airports_continent ON airports(continent)")
dbExecute(con, "CREATE INDEX idx_airlines_iata ON airlines(iata_code)")
dbExecute(con, "CREATE INDEX idx_routes_origin ON routes(origin_iata)")
dbExecute(con, "CREATE INDEX idx_routes_dest ON routes(dest_iata)")
dbExecute(con, "CREATE INDEX idx_routes_airline ON routes(airline_iata)")
dbExecute(con, "CREATE INDEX idx_routes_pair ON routes(origin_iata, dest_iata)")

# ---- European convenience views ----
dbExecute(con, "
  CREATE VIEW europe_airports AS
  SELECT * FROM airports WHERE continent = 'EU'
")

dbExecute(con, "
  CREATE VIEW europe_routes AS
  SELECT r.*, ao.city AS origin_city, ao.country AS origin_country,
         ad.city AS dest_city, ad.country AS dest_country
  FROM routes r
  JOIN airports ao ON r.origin_iata = ao.iata_code AND ao.continent = 'EU'
  JOIN airports ad ON r.dest_iata   = ad.iata_code AND ad.continent = 'EU'
")

# ---- Summary ----
cat("\n--- Database summary ---\n")
cat("Path:", db_path, "\n")
cat("Data date:", format(file.mtime(json_path), "%Y-%m-%d"), "\n")
for (tbl in dbListTables(con)) {
  n <- dbGetQuery(con, paste0("SELECT COUNT(*) AS n FROM ", tbl))$n
  cat(" ", tbl, ":", n, "rows\n")
}

dbDisconnect(con)
cat("Done.\n")
