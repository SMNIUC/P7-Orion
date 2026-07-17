#!/usr/bin/env bash
# =============================================================================
# Import du tableau de bord Kibana - Orion MicroCRM
#
# Recree le data view, les 7 visualisations et le dashboard a partir du fichier
# versionne misc/elk/kibana/microcrm-dashboard.ndjson.
#
# Pourquoi un fichier + un script plutot qu'une construction a la souris :
# les objets Kibana vivent dans le volume "elasticsearch-data". Un
# "docker compose down -v" les detruit. Versionner l'export rend le tableau de
# bord REPRODUCTIBLE (et relisible en revue de code) au lieu d'etre un etat
# local non tracable.
#
# Usage : ./misc/elk/import-dashboard.sh
# =============================================================================

set -euo pipefail

KIBANA="${KIBANA_URL:-http://localhost:5601}"
FICHIER="$(cd "$(dirname "$0")" && pwd)/kibana/microcrm-dashboard.ndjson"

if [ ! -f "$FICHIER" ]; then
  echo "ERREUR : fichier introuvable : $FICHIER" >&2
  exit 1
fi

echo "Attente de Kibana sur ${KIBANA} ..."
for i in $(seq 1 60); do
  # Kibana repond 200 sur /api/status une fois pret (compter ~2 min au 1er
  # demarrage : l'initialisation est lente avec 512 Mo de heap).
  if curl -fsS -o /dev/null "${KIBANA}/api/status" 2>/dev/null; then
    echo "Kibana est pret."
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "ERREUR : Kibana n'a pas repondu en 5 minutes." >&2
    echo "Verifiez : docker compose -f docker-compose.yml -f docker-compose.elk.yml ps" >&2
    exit 1
  fi
  sleep 5
done

echo "Import des objets Kibana..."
reponse=$(curl -sS -X POST "${KIBANA}/api/saved_objects/_import?overwrite=true" \
  -H "kbn-xsrf: true" \
  --form "file=@${FICHIER}")

echo "$reponse" | KIBANA="$KIBANA" python3 -c '
import json, os, sys

r = json.load(sys.stdin)
if r.get("success"):
    print("OK :", r.get("successCount"), "objets importes.")
    print("Tableau de bord :", os.environ["KIBANA"] + "/app/dashboards#/view/microcrm-dashboard")
else:
    print("ECHEC de limport :")
    for e in r.get("errors", []):
        print("  -", e.get("type"), e.get("id"), ":", e.get("error", {}).get("type"))
    sys.exit(1)
'
