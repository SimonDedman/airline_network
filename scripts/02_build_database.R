# 02_build_database.R
# Clean downloaded data and build SQLite database
#
# Run 01_download_data.R first.

library(data.table)
library(DBI)
library(RSQLite)

data_dir <- file.path(here::here(), "data")
db_dir   <- file.path(here::here(), "db")
dir.create(db_dir, showWarnings = FALSE, recursive = TRUE)

db_path <- file.path(db_dir, "airline_network.sqlite")

# Remove old DB if rebuilding
if (file.exists(db_path)) file.remove(db_path)

con <- dbConnect(SQLite(), db_path)

# ---- Airports (OurAirports) ----
cat("Building airports table...\n")

airports_raw <- fread(
  file.path(data_dir, "ourairports_airports.csv"),
  na.strings = ""
)

# Keep medium and large airports (skip helipads, closed, small strips)
airports <- airports_raw[
  type %in% c("large_airport", "medium_airport"),
  .(
    oa_id        = id,
    ident        = ident,
    iata_code    = iata_code,
    name         = name,
    city         = municipality,
    iso_country  = iso_country,
    iso_region   = iso_region,
    latitude     = latitude_deg,
    longitude    = longitude_deg,
    elevation_ft = elevation_ft,
    type         = type,
    scheduled_service = scheduled_service
  )
]

# Drop rows with no IATA code (can't join to routes)
airports <- airports[!is.na(iata_code) & iata_code != ""]

# Deduplicate on IATA code (keep large_airport over medium)
airports[, type_rank := fifelse(type == "large_airport", 1L, 2L)]
airports <- airports[order(iata_code, type_rank)]
airports <- airports[!duplicated(iata_code)]
airports[, type_rank := NULL]

# Add country names from OurAirports countries file
countries <- fread(
  file.path(data_dir, "ourairports_countries.csv"),
  na.strings = ""
)
airports <- merge(
  airports,
  countries[, .(iso_country = code, country = name, continent)],
  by = "iso_country",
  all.x = TRUE
)

# Add region names
regions <- fread(
  file.path(data_dir, "ourairports_regions.csv"),
  na.strings = ""
)
airports <- merge(
  airports,
  regions[, .(iso_region = code, region = name)],
  by = "iso_region",
  all.x = TRUE
)

dbWriteTable(con, "airports", airports, overwrite = TRUE)
cat("  ", nrow(airports), "airports loaded\n")


# ---- Airlines (OpenFlights) ----
cat("Building airlines table...\n")

airlines_raw <- fread(
  file.path(data_dir, "openflights_airlines.dat"),
  header = FALSE,
  na.strings = c("\\N", ""),
  quote = "\""
)
setnames(airlines_raw, c(
  "of_id", "name", "alias", "iata_code", "icao_code",
  "callsign", "country", "active"
))

airlines <- airlines_raw[
  active == "Y" & !is.na(iata_code) & iata_code != "",
  .(iata_code, icao_code, name, country, active)
]

# Deduplicate on IATA code (keep first)
airlines <- airlines[!duplicated(iata_code)]

dbWriteTable(con, "airlines", airlines, overwrite = TRUE)
cat("  ", nrow(airlines), "active airlines loaded\n")


# ---- Routes (OpenFlights) ----
cat("Building routes table...\n")

routes_raw <- fread(
  file.path(data_dir, "openflights_routes.dat"),
  header = FALSE,
  na.strings = c("\\N", ""),
  quote = "\""
)
setnames(routes_raw, c(
  "airline_iata", "airline_of_id", "origin_iata", "origin_of_id",
  "dest_iata", "dest_of_id", "codeshare", "stops", "equipment"
))

routes <- routes_raw[
  !is.na(origin_iata) & !is.na(dest_iata) & !is.na(airline_iata),
  .(
    airline_iata,
    origin_iata,
    dest_iata,
    codeshare = fifelse(codeshare == "Y", TRUE, FALSE),
    stops     = as.integer(stops),
    equipment
  )
]

# Tag routes where both endpoints exist in our airports table
valid_iata <- airports$iata_code
routes[, origin_known := origin_iata %in% valid_iata]
routes[, dest_known   := dest_iata   %in% valid_iata]

dbWriteTable(con, "routes", routes, overwrite = TRUE)
cat("  ", nrow(routes), "routes loaded (",
    nrow(routes[origin_known == TRUE & dest_known == TRUE]),
    "with both airports known)\n")


# ---- Indexes ----
cat("Creating indexes...\n")
dbExecute(con, "CREATE INDEX idx_airports_iata ON airports(iata_code)")
dbExecute(con, "CREATE INDEX idx_airports_country ON airports(iso_country)")
dbExecute(con, "CREATE INDEX idx_airports_continent ON airports(continent)")
dbExecute(con, "CREATE INDEX idx_airlines_iata ON airlines(iata_code)")
dbExecute(con, "CREATE INDEX idx_routes_origin ON routes(origin_iata)")
dbExecute(con, "CREATE INDEX idx_routes_dest ON routes(dest_iata)")
dbExecute(con, "CREATE INDEX idx_routes_airline ON routes(airline_iata)")
dbExecute(con, "CREATE INDEX idx_routes_pair ON routes(origin_iata, dest_iata)")

# ---- European convenience view ----
cat("Creating European views...\n")
dbExecute(con, "
  CREATE VIEW europe_airports AS
  SELECT * FROM airports
  WHERE continent = 'EU'
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
for (tbl in dbListTables(con)) {
  n <- dbGetQuery(con, paste0("SELECT COUNT(*) AS n FROM ", tbl))$n
  cat(" ", tbl, ":", n, "rows\n")
}

dbDisconnect(con)
cat("Done.\n")
