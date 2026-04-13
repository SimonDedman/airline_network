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

**routes** — ~67K airline routes
- `airline_iata`, `origin_iata`, `dest_iata`
- `codeshare` (TRUE/FALSE), `stops` (usually 0), `equipment` (aircraft types)
- `origin_known`, `dest_known` (whether both endpoints are in airports table)

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
- **OpenFlights** (routes, airlines): ODbL, route data frozen ~June 2014

Route data is stale but structurally sound for identifying which
airports connect to which. Major European routes (Ryanair, Aer Lingus,
easyJet hubs) are well represented.

## Rebuilding the database

```r
source("R/01_download_data.R")  # downloads CSVs to data/
source("R/02_build_database.R") # builds db/airline_network.sqlite
```

Requires: DBI, RSQLite, data.table, curl, here
