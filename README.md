# airline_network

A queryable SQLite database of global airline routes, built from open data sources.

## Setup

```r
install.packages(c("DBI", "RSQLite", "data.table", "curl", "here"))

source("R/01_download_data.R")  # download data (~5 MB)
source("R/02_build_database.R") # build SQLite database
```

## Usage

```r
source("R/03_query_helpers.R")
db <- an_connect()

# Search airports
airport_search(db, "shannon")

# Direct flights from Shannon
routes_from(db, "SNN")
routes_from(db, "SNN", europe = TRUE)

# Ryanair destinations from Shannon
routes_from(db, "SNN", airline = "FR")

# Find routes Shannon to Athens (direct + 1-stop)
connections(db, "SNN", "ATH")

# Airlines operating from Dublin
airlines_at(db, "DUB")

# Countries reachable from Cork
countries_from(db, "ORK", europe = TRUE)

# Arbitrary SQL
an_query(db, "SELECT * FROM europe_routes WHERE origin_iata = 'SNN'")

an_disconnect(db)
```

## Data sources

| Source | Coverage | Licence | Freshness |
|--------|----------|---------|-----------|
| [OurAirports](https://ourairports.com/data/) | 78K+ airports | Public domain | Updated weekly |
| [OpenFlights](https://openflights.org/data.php) | 67K routes, 6K airlines | ODbL | Routes frozen ~2014 |

## Licence

Code: MIT. Data files (in `data/` and `db/`) are subject to their
respective upstream licences and are gitignored.
