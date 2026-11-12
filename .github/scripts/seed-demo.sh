#!/usr/bin/env bash
# Siembra el backend local con usuarios y avisos alrededor de la Puerta del Sol (Madrid)
# para las pruebas de interfaz. Usa la API real; solo envejece las cuentas por SQL.
set -euo pipefail
API=${API:-http://localhost:8080}
DB=${DATABASE_URL:-postgres://nex:nex@localhost:5432/nex}

register() {
  curl -fsS -X POST "$API/v1/auth/register" -H 'content-type: application/json' \
    -d "{\"email\":\"$1@nex.test\",\"password\":\"clave-de-siembra-1\",\"displayName\":\"$1\"}" | jq -r .accessToken
}
report() { # token tipo lat lon
  curl -fsS -X POST "$API/v1/alerts" -H "authorization: Bearer $1" -H 'content-type: application/json' \
    -d "{\"type\":\"$2\",\"lat\":$3,\"lon\":$4,\"reporterLat\":$3,\"reporterLon\":$4,\"country\":\"ES\"}" | jq -r .alert.id
}
vote() { # token id voto lat lon
  curl -fsS -X POST "$API/v1/alerts/$2/votes" -H "authorization: Bearer $1" -H 'content-type: application/json' \
    -d "{\"vote\":\"$3\",\"lat\":$4,\"lon\":$5}" > /dev/null
}

A=$(register ana); B=$(register bruno); C=$(register carla)
psql "$DB" -qc "UPDATE users SET created_at = now() - interval '30 days' WHERE email IN ('ana@nex.test','bruno@nex.test','carla@nex.test')"
N=$(register novato)   # cuenta nueva: su aviso sale como "sin verificar"

ACC=$(report "$A" accident 40.4215 -3.7010)
vote "$B" "$ACC" confirm 40.4215 -3.7010
vote "$C" "$ACC" confirm 40.4215 -3.7010
JAM=$(report "$A" traffic_jam 40.4260 -3.6935)
vote "$B" "$JAM" confirm 40.4260 -3.6935
report "$B" roadworks 40.4135 -3.7105 > /dev/null
report "$C" police 40.4302 -3.6890 > /dev/null
report "$B" stopped_vehicle 40.4190 -3.6960 > /dev/null
report "$N" hazard 40.4150 -3.6990 > /dev/null
psql "$DB" -qc "INSERT INTO alerts (type, lat, lon, country, source) VALUES ('speed_camera', 40.4330, -3.6880, 'ES', 'official'), ('speed_camera', 40.4095, -3.7180, 'ES', 'official')"
echo "Avisos sembrados: $(curl -fsS "$API/v1/alerts?lat=40.4168&lon=-3.7038&radius=5000" | jq '.alerts | length')"
