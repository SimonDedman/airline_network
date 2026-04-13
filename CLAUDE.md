# airline_network

Queryable SQLite database of global airline routes. Primary use case:
planning European summer holidays from Irish/UK airports.

## Database

Path: `db/airline_network.sqlite`

### Tables

**airports** — ~4K medium/large airports worldwide
- `iata_code` (PK-like), `name`, `city`, `country`, `continent`, `iso_country`, `iso_region`, `region`
- `latitude`, `longitude`, `elevation_ft`, `type` (large_airport / medium_airport)
- `scheduled_service` (yes/no)

**airlines** — ~1K active airlines
- `iata_code` (PK-like), `icao_code`, `name`, `country`, `active`

**routes** — ~90K airline routes (weekly-updated via Jonty/airline-route-data)
- `airline_iata`, `origin_iata`, `dest_iata`
- `distance_km`, `flight_min` (flight duration in minutes)
- `source` (currently "jonty" for all rows)

### Views

- `europe_airports` — airports where continent = 'EU'
- `europe_routes` — routes where both endpoints are in Europe, with city/country joined

### Key joins

```sql
-- Routes with full airport info
SELECT r.*, ao.city AS origin_city, ad.city AS dest_city
FROM routes r
JOIN airports ao ON r.origin_iata = ao.iata_code
JOIN airports ad ON r.dest_iata = ad.iata_code

-- 1-stop connections from A to B
SELECT r1.origin_iata, r1.dest_iata AS via, r2.dest_iata
FROM routes r1
JOIN routes r2 ON r1.dest_iata = r2.origin_iata
WHERE r1.origin_iata = 'SNN' AND r2.dest_iata = 'ATH'
```

## Querying

Use `R/03_query_helpers.R` for convenience functions, or query the
SQLite directly. The `an_query(con, sql)` function runs arbitrary SQL.

### Irish airports

SNN (Shannon), DUB (Dublin), ORK (Cork), NOC (Knock/Ireland West),
KIR (Kerry), WAT (Waterford — limited service)

## Data sources

- **OurAirports** (airports): public domain, updated weekly
- **Jonty/airline-route-data** (routes, airlines): GitHub, updated weekly
  https://github.com/Jonty/airline-route-data
- **OpenFlights** (legacy, still downloaded but superseded by Jonty)

## Rebuilding the database

```r
source("scripts/01_download_data.R")   # downloads OurAirports CSVs
source("scripts/04_ingest_jonty.R")    # downloads Jonty JSON + builds SQLite
```

To refresh route data only (re-downloads if >7 days old):
```r
source("scripts/04_ingest_jonty.R")
```

Note: build scripts live in `scripts/`, not `R/`. Shiny 1.13+
auto-sources everything in `R/` on app startup.

Requires: DBI, RSQLite, data.table, jsonlite, curl, here
