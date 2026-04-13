# 05_export_static.R
# Export database to compact JSON for the static GitHub Pages site.

library(DBI)
library(RSQLite)
library(data.table)
library(jsonlite)

db_path  <- file.path(here::here(), "db", "airline_network.sqlite")
out_path <- file.path(here::here(), "docs", "data.json")
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)

con <- dbConnect(SQLite(), db_path)

airports <- as.data.table(dbGetQuery(con, "
  SELECT iata_code, name, city, country, continent, latitude, longitude, type
  FROM airports
  WHERE latitude IS NOT NULL AND longitude IS NOT NULL
"))

routes <- as.data.table(dbGetQuery(con, "
  SELECT airline_iata, origin_iata, dest_iata, distance_km, flight_min
  FROM routes
"))

airlines <- as.data.table(dbGetQuery(con, "
  SELECT iata_code, name FROM airlines
"))

dbDisconnect(con)

# Compact airport format: keyed by IATA
airports[, latitude := as.numeric(latitude)]
airports[, longitude := as.numeric(longitude)]
airports <- airports[!is.na(latitude) & !is.na(longitude)]
airports[, type_short := fifelse(type == "large_airport" & !is.na(type), "L", "M")]
apt_list <- setNames(
  lapply(seq_len(nrow(airports)), function(i) {
    a <- airports[i]
    list(
      n  = a$name,
      c  = a$city,
      co = a$country,
      ct = a$continent,
      la = round(a$latitude, 4),
      lo = round(a$longitude, 4),
      t  = a$type_short
    )
  }),
  airports$iata_code
)

# Compact airline format: iata -> name
arl_list <- setNames(as.list(airlines$name), airlines$iata_code)

# Compact route format: array of arrays [airline, origin, dest, km, min]
routes_arr <- lapply(seq_len(nrow(routes)), function(i) {
  r <- routes[i]
  list(r$airline_iata, r$origin_iata, r$dest_iata,
       r$distance_km, r$flight_min)
})

data_out <- list(
  airports = apt_list,
  airlines = arl_list,
  routes   = routes_arr
)

cat("Exporting", length(apt_list), "airports,",
    length(arl_list), "airlines,",
    length(routes_arr), "routes\n")

json_str <- toJSON(data_out, auto_unbox = TRUE, null = "null")
writeLines(json_str, out_path)

cat("Written to:", out_path, "\n")
cat("Size:", format(file.size(out_path) / 1e6, digits = 3), "MB\n")
