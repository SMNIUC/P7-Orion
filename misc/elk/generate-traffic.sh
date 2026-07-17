#!/usr/bin/env bash
# =============================================================================
# Generateur de trafic de demonstration - Orion MicroCRM
#
# Produit un trafic REEL et reproductible contre l'application, pour alimenter
# la stack ELK et rendre les tableaux de bord Kibana demonstratifs.
#
# Important : ce script n'injecte AUCUNE donnee dans Elasticsearch. Il ne fait
# qu'appeler l'application ; les logs sont ensuite produits, collectes et
# indexes par la chaine normale (Tomcat/Caddy -> Logstash -> ES). Ce que le
# dashboard affiche est donc bien du trafic authentique.
#
# Prerequis : la stack tourne
#   docker compose -f docker-compose.yml -f docker-compose.elk.yml up -d
#
# Usage : ./misc/elk/generate-traffic.sh [nombre_de_cycles]   (defaut : 20)
# =============================================================================

set -uo pipefail

FRONT="http://localhost:4200"
API="http://localhost:8080"
CYCLES="${1:-20}"

# Verifie que l'application repond avant de commencer.
if ! curl -fsS -o /dev/null "${API}/" 2>/dev/null; then
  echo "ERREUR : l'API ne repond pas sur ${API}." >&2
  echo "Demarrez la stack :" >&2
  echo "  docker compose -f docker-compose.yml -f docker-compose.elk.yml up -d" >&2
  exit 1
fi

# Appelle une URL et affiche le statut obtenu.
appel() {
  local methode="$1" url="$2" attendu="${3:-}"
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -X "$methode" "$url" 2>/dev/null || echo "000")
  if [ -n "$attendu" ] && [ "$code" != "$attendu" ]; then
    printf '  %-6s %-45s -> %s (attendu %s)\n' "$methode" "$url" "$code" "$attendu"
  else
    printf '  %-6s %-45s -> %s\n' "$methode" "$url" "$code"
  fi
}

echo "Generation de ${CYCLES} cycles de trafic..."
echo

for i in $(seq 1 "$CYCLES"); do
  # --- Trafic nominal (majoritaire, comme en usage reel) ---
  curl -s -o /dev/null "${FRONT}/"                  # page front (Caddy)
  curl -s -o /dev/null "${API}/organizations"       # API : liste
  curl -s -o /dev/null "${API}/persons"             # API : liste
  curl -s -o /dev/null "${API}/organizations/1"     # API : detail
  curl -s -o /dev/null "${API}/organizations/1/persons"

  # --- Trafic d'erreur (minoritaire : ~1 cycle sur 5) ---
  # Objectif : que le dashboard "erreurs" ait de quoi montrer, avec des
  # erreurs AUTHENTIQUES et non simulees.
  if [ $((i % 5)) -eq 0 ]; then
    # 404 : ressource inexistante (erreur client, attendue).
    curl -s -o /dev/null "${API}/persons/99999"
    # 500 : identifiant non numerique -> echec de conversion cote back.
    #       Anomalie reelle : l'API repond 500 la ou un 400 serait correct.
    curl -s -o /dev/null "${API}/organizations/abc"
    # 405 : methode refusee par le file_server de Caddy (erreur cote front).
    curl -s -o /dev/null -X POST "${FRONT}/"
  fi
done

echo "Trafic genere. Verification des statuts caracteristiques :"
appel GET  "${API}/organizations"     200
appel GET  "${API}/persons/99999"     404
appel GET  "${API}/organizations/abc" 500
appel POST "${FRONT}/"                405
echo
echo "Les logs mettent ~10 s a apparaitre dans Kibana (cycle de lecture Logstash)."
echo "Tableau de bord : http://localhost:5601/app/dashboards"
