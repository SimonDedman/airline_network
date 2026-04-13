# 03_query_helpers.R
# Convenience functions for querying the airline network database.
#
# Usage:
#   source("R/03_query_helpers.R")
#   db <- an_connect()
#   routes_from(db, "SNN")              # direct flights from Shannon
#   routes_from(db, "SNN", europe = TRUE)
#   connections(db, "SNN", "ATH")       # Shannon to Athens with 1 stop
#   airport_search(db, "shannon")
#   an_disconnect(db)

library(DBI)
library(RSQLite)
library(data.table)

# ---- Connection helpers ----

an_connect <- function(db_path = NULL) {
  if (is.null(db_path)) {
    db_path <- file.path(here::here(), "db", "airline_network.sqlite")
  }
  if (!file.exists(db_path)) {
    stop("Database not found at ", db_path, ". Run 01 and 02 scripts first.")
  }
  dbConnect(SQLite(), db_path)
}

an_disconnect <- function(con) dbDisconnect(con)

# ---- Airport lookup ----

#' Search airports by name, city, IATA code, or country
airport_search <- function(con, query, continent = NULL) {
  sql <- "
    SELECT iata_code, name, city, country, continent, iso_country,
           latitude, longitude, type
    FROM airports
    WHERE (iata_code LIKE ?1 OR LOWER(name) LIKE ?2
           OR LOWER(city) LIKE ?2 OR LOWER(country) LIKE ?2)
  "
  params <- list(toupper(query), paste0("%", tolower(query), "%"))

  if (!is.null(continent)) {
    sql <- paste(sql, "AND continent = ?3")
    params <- c(params, list(toupper(continent)))
  }

  sql <- paste(sql, "ORDER BY type, name")
  as.data.table(dbGetQuery(con, sql, params = params))
}

# ---- Direct routes ----

#' All direct destinations from an airport
routes_from <- function(con, origin, airline = NULL, europe = FALSE) {
  sql <- "
    SELECT r.airline_iata, al.name AS airline_name,
           r.dest_iata, a.name AS dest_airport, a.city AS dest_city,
           a.country AS dest_country, a.continent AS dest_continent,
           r.codeshare, r.stops, r.equipment
    FROM routes r
    LEFT JOIN airports a ON r.dest_iata = a.iata_code
    LEFT JOIN airlines al ON r.airline_iata = al.iata_code
    WHERE r.origin_iata = ?1
  "
  params <- list(toupper(origin))

  if (!is.null(airline)) {
    sql <- paste(sql, "AND r.airline_iata = ?2")
    params <- c(params, list(toupper(airline)))
  }

  if (europe) {
    sql <- paste(sql, "AND a.continent = 'EU'")
  }

  sql <- paste(sql, "ORDER BY a.country, a.city")
  as.data.table(dbGetQuery(con, sql, params = params))
}

#' All direct origins to an airport
routes_to <- function(con, dest, airline = NULL, europe = FALSE) {
  sql <- "
    SELECT r.airline_iata, al.name AS airline_name,
           r.origin_iata, a.name AS origin_airport, a.city AS origin_city,
           a.country AS origin_country, a.continent AS origin_continent,
           r.codeshare, r.stops, r.equipment
    FROM routes r
    LEFT JOIN airports a ON r.origin_iata = a.iata_code
    LEFT JOIN airlines al ON r.airline_iata = al.iata_code
    WHERE r.dest_iata = ?1
  "
  params <- list(toupper(dest))

  if (!is.null(airline)) {
    sql <- paste(sql, "AND r.airline_iata = ?2")
    params <- c(params, list(toupper(airline)))
  }

  if (europe) {
    sql <- paste(sql, "AND a.continent = 'EU'")
  }

  sql <- paste(sql, "ORDER BY a.country, a.city")
  as.data.table(dbGetQuery(con, sql, params = params))
}

# ---- Connections (1-stop) ----

#' Find routes between two airports with at most 1 connection
connections <- function(con, from, to, europe_only = FALSE) {
  from <- toupper(from)
  to   <- toupper(to)

  # Check direct routes first
  direct_sql <- "
    SELECT r.airline_iata, al.name AS airline_name,
           r.origin_iata, r.dest_iata,
           NULL AS via_iata, NULL AS via_city,
           'direct' AS route_type,
           r.equipment
    FROM routes r
    LEFT JOIN airlines al ON r.airline_iata = al.iata_code
    WHERE r.origin_iata = ?1 AND r.dest_iata = ?2
  "
  direct <- as.data.table(dbGetQuery(con, direct_sql, params = list(from, to)))

  # 1-stop connections
  connect_sql <- "
    SELECT r1.airline_iata AS airline_1, r2.airline_iata AS airline_2,
           r1.origin_iata, r1.dest_iata AS via_iata,
           a_via.city AS via_city, a_via.country AS via_country,
           r2.dest_iata,
           '1-stop' AS route_type
    FROM routes r1
    JOIN routes r2 ON r1.dest_iata = r2.origin_iata
    JOIN airports a_via ON r1.dest_iata = a_via.iata_code
    WHERE r1.origin_iata = ?1 AND r2.dest_iata = ?2
  "

  if (europe_only) {
    connect_sql <- paste(connect_sql, "AND a_via.continent = 'EU'")
  }

  connect_sql <- paste(connect_sql, "ORDER BY a_via.city")
  connecting <- as.data.table(dbGetQuery(con, connect_sql, params = list(from, to)))

  list(direct = direct, connecting = connecting)
}

# ---- Network summaries ----

#' Airlines operating from an airport
airlines_at <- function(con, airport) {
  sql <- "
    SELECT DISTINCT r.airline_iata, al.name AS airline_name,
           COUNT(*) AS n_destinations
    FROM routes r
    LEFT JOIN airlines al ON r.airline_iata = al.iata_code
    WHERE r.origin_iata = ?1
    GROUP BY r.airline_iata, al.name
    ORDER BY n_destinations DESC
  "
  as.data.table(dbGetQuery(con, sql, params = list(toupper(airport))))
}

#' Countries reachable from an airport (direct flights)
countries_from <- function(con, airport, europe = FALSE) {
  sql <- "
    SELECT DISTINCT a.iso_country, a.country, a.continent,
           COUNT(DISTINCT r.dest_iata) AS n_airports
    FROM routes r
    JOIN airports a ON r.dest_iata = a.iata_code
    WHERE r.origin_iata = ?1
  "
  if (europe) sql <- paste(sql, "AND a.continent = 'EU'")
  sql <- paste(sql, "GROUP BY a.iso_country, a.country, a.continent
                      ORDER BY n_airports DESC")
  as.data.table(dbGetQuery(con, sql, params = list(toupper(airport))))
}

#' Run arbitrary SQL (for Claude Code / LLM queries)
an_query <- function(con, sql) {
  as.data.table(dbGetQuery(con, sql))
}
