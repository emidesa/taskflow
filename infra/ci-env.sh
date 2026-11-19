#!/usr/bin/env bash
# ============================================================================
# ci-env.sh : prépare les variables OpenTofu (TF_VAR_*) d'un job GitHub Actions.
# Utilisé par iac.yml (plan) et release.yml (deploy-staging), APRÈS `tofu init`,
# depuis le dossier infra/ :
#
#     ./ci-env.sh            # garde la version déjà déployée (lue dans le state)
#     ./ci-env.sh a1b2c3d    # version à déployer
#
# Écrit dans $GITHUB_ENV (variables visibles par les steps suivants du job) :
#   TF_VAR_ghcr_owner   propriétaire du dépôt, EN MINUSCULES (exigé par ghcr.io)
#   TF_VAR_image_tag    tag demandé, sinon output « image_tag » du state, sinon latest
#   TF_VAR_db_password  POSTGRES_PASSWORD de $STAGING_DIR/.env s'il existe (volume
#                       créé par le staging Compose du Jour 3), masqué dans les logs
# ============================================================================
set -euo pipefail

: "${GITHUB_ENV:?à lancer dans un job GitHub Actions}"
: "${GITHUB_REPOSITORY_OWNER:?variable GitHub absente}"

tag="${1:-}"
if [ -z "$tag" ]; then
  # Pas de state (premier déploiement) : tofu output échoue -> latest
  tag="$(tofu output -raw image_tag 2>/dev/null || true)"
  tag="${tag:-latest}"
fi
if [[ ! "$tag" =~ ^([0-9a-f]{7}|latest)$ ]]; then
  echo "::error::Tag invalide : '$tag'" >&2
  exit 1
fi

{
  echo "TF_VAR_ghcr_owner=${GITHUB_REPOSITORY_OWNER,,}"
  echo "TF_VAR_image_tag=$tag"
} >> "$GITHUB_ENV"

env_file="${STAGING_DIR:-}/.env"
if [ -n "${STAGING_DIR:-}" ] && [ -f "$env_file" ]; then
  password="$(sed -n 's/^POSTGRES_PASSWORD=//p' "$env_file" | tail -n 1)"
  if [ -n "$password" ]; then
    echo "::add-mask::$password"
    echo "TF_VAR_db_password=$password" >> "$GITHUB_ENV"
  fi
fi

echo "Variables OpenTofu prêtes : owner=${GITHUB_REPOSITORY_OWNER,,}, image_tag=$tag"
