# airline_network

A queryable database of global airline routes with an interactive map explorer.

**[Live demo](https://simondedman.github.io/airline_network/)** -- no install needed, runs in your browser.

## Features

- Interactive Leaflet map with 5,300+ airports and 90,000+ routes
- Click airports to see all direct destinations
- Multi-select origins and destinations (Ctrl+click) to find 1-stop connections
- Pin connection airports for detailed inbound/outbound airline info
- Copy connection reports to clipboard
- Also available as a local Shiny app with SQLite backend

## Live map

Visit **https://simondedman.github.io/airline_network/** to use the browser version directly.

## Local setup (R/Shiny)

```r
install.packages(c("DBI", "RSQLite", "data.table", "jsonlite", "curl", "here"))

source("scripts/01_download_data.R")   # download airport data
source("scripts/04_ingest_jonty.R")    # download routes + build SQLite database

# Launch the Shiny app
shiny::runApp("app.R")
```

## R query helpers

```r
source("R/03_query_helpers.R")
db <- an_connect()

airport_search(db, "shannon")
routes_from(db, "SNN", europe = TRUE)
routes_from(db, "SNN", airline = "FR")
connections(db, "SNN", "ATH")
airlines_at(db, "DUB")
countries_from(db, "ORK", europe = TRUE)
an_query(db, "SELECT * FROM europe_routes WHERE origin_iata = 'SNN'")

an_disconnect(db)
```

## Data sources

| Source | Coverage | Licence | Freshness |
|--------|----------|---------|-----------|
| [Jonty/airline-route-data](https://github.com/Jonty/airline-route-data) | 3,900 airports, 90K routes | Public GitHub | Updated weekly |
| [OurAirports](https://ourairports.com/data/) | 78K+ airports | Public domain | Updated weekly |

## Licence

Code: MIT. Data files (in `data/` and `db/`) are subject to their
respective upstream licences and are gitignored.
