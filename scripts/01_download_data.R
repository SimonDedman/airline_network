# 01_download_data.R
# Download airline route data from free/open sources
#
# Sources:
#   OurAirports (public domain) - 78K+ airports, actively maintained
#   OpenFlights (ODbL)          - routes, airlines (routes frozen ~2014)

library(data.table)
library(curl)

data_dir <- file.path(here::here(), "data")
dir.create(data_dir, showWarnings = FALSE, recursive = TRUE)

cat("Downloading OurAirports data...\n")

# Airports (public domain, updated weekly)
curl_download(
  "https://davidmegginson.github.io/ourairports-data/airports.csv",
  file.path(data_dir, "ourairports_airports.csv")
)

# Country reference
curl_download(
  "https://davidmegginson.github.io/ourairports-data/countries.csv",
  file.path(data_dir, "ourairports_countries.csv")
)

# Regions (for mapping iso_region codes to names)
curl_download(
  "https://davidmegginson.github.io/ourairports-data/regions.csv",
  file.path(data_dir, "ourairports_regions.csv")
)

cat("Downloading OpenFlights data...\n")

# Routes (ODbL - last updated ~June 2014, but structure is sound)
curl_download(
  "https://raw.githubusercontent.com/jpatokal/openflights/master/data/routes.dat",
  file.path(data_dir, "openflights_routes.dat")
)

# Airlines
curl_download(
  "https://raw.githubusercontent.com/jpatokal/openflights/master/data/airlines.dat",
  file.path(data_dir, "openflights_airlines.dat")
)

# Airports (supplement — OpenFlights has IATA codes OurAirports sometimes lacks)
curl_download(
  "https://raw.githubusercontent.com/jpatokal/openflights/master/data/airports.dat",
  file.path(data_dir, "openflights_airports.dat")
)

cat("All downloads complete. Files in:", data_dir, "\n")
