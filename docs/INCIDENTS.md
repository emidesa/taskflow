# Incidents de production

Post-mortems sans blâme : on cherche ce qui a permis l'incident (processus, outillage), pas qui l'a provoqué.
Du plus récent au plus ancien.

## Méthode de diagnostic

1. **Alerte** : laquelle, depuis quand, quelle cible (Alertmanager http://localhost:9093, Prometheus > *Alerts*).
2. **Dashboard** Grafana (http://localhost:3001) : heure de passage « EN PANNE », la version a-t-elle changé ?
3. **Symptôme** : `curl -sk https://taskflow.localhost/health`.
4. **Conteneurs** : `docker compose -f compose.prod.yaml ps` dans `~/taskflow-prod`.
5. **Logs** : `docker compose -f compose.prod.yaml logs --no-log-prefix --since 15m api | jq -c 'select(.level != "info")'`.
6. **Cause racine** : la prouver (ce que reçoit le conteneur, ce que contient la configuration), pas la deviner.

---

## Incident n° 1 - L'API redémarre en boucle après une modification du `.env`

**Gravité** : élevée (application indisponible pour tous les utilisateurs)
**Détection** : alerte `TaskFlowApiDown` (mail Mailpit) - délai entre le début et la détection : 1 min 36 s
**Durée** : début 16:45:09 - fin 16:50:45 (heure de Paris), soit 5 min 36 s (MTTR)
**Rédaction** : Emeline De Sa

### Résumé
Après la recréation du conteneur `api` de production, l'API ne démarrait plus et redémarrait en boucle.
Pendant 5 min 36 s, https://taskflow.localhost renvoyait une **502** : aucun utilisateur ne pouvait consulter
ni créer de tâche. Aucune donnée n'a été perdue (la base est restée en ligne).

### Chronologie (heure de Paris, UTC+1)
- 16:45:09 - Le conteneur `api` est recréé avec un `.env` où `DATABASE_URL` est renommée `DATABASE_UR`
- 16:45:17 - Premier log `fatal` : `Démarrage impossible : ECONNREFUSED` ; l'API passe en `Restarting (1)`
- 16:46:30 - Mail `[FIRING]` `TaskFlowMetricsDown` (warning) : Prometheus ne lit plus `api:3000/metrics`
- 16:46:45 - **Premier signal critique** : mail `[FIRING]` `TaskFlowApiDown` (sonde `http://front/health` en échec)
- 16:47 - `curl /health` : **502 Bad Gateway** (Nginx vivant, API injoignable)
- 16:47 - `docker compose ps` : `api` en `Restarting (1)`, même image `ec41e75`, recréée 2 min plus tôt ; `db` *healthy*
- 16:48 - Logs filtrés avec `jq` : `ECONNREFUSED`, hint « Vérifiez DATABASE_URL »
- 16:49 - `docker inspect` (noms des variables) et `.env` : `DATABASE_UR` au lieu de `DATABASE_URL` -> cause prouvée
- 16:49:30 - Correction : nom de la variable rétabli dans `.env`, conteneur `api` recréé
- 16:50 - `ps` : 4 services *healthy* ; `/health` = `ok` ; création d'une tâche réussie
- 16:50:45 - Mail `[RESOLVED]` `TaskFlowApiDown` : retour à la normale confirmé

### Cause racine (5 pourquoi)
1. Pourquoi le site renvoyait-il une 502 ? Le proxy et le front ne joignaient plus l'API.
2. Pourquoi l'API était-elle injoignable ? Elle s'arrêtait au démarrage (`ECONNREFUSED`) et redémarrait en boucle.
3. Pourquoi `ECONNREFUSED` alors que la base était *healthy* ? L'API se connectait à `localhost:5432` (valeur par
   défaut de `config.js`), c'est-à-dire à son propre conteneur, sans PostgreSQL.
4. Pourquoi la valeur par défaut ? La variable `DATABASE_URL` était absente : le `.env` contenait `DATABASE_UR`.
5. Pourquoi une variable mal nommée a-t-elle pu atteindre la production ? Rien ne vérifie le `.env` : l'API accepte
   de démarrer en production sans `DATABASE_URL`, et le déploiement ne compare pas `.env` à `.env.example`.

### Ce qui a bien fonctionné
- L'alerte `TaskFlowApiDown` est arrivée 1 min 36 s après le début, avant tout signalement d'utilisateur.
- La sonde à travers le front a mesuré ce que voit l'utilisateur (502), pas seulement l'état d'un conteneur.
- Les logs JSON filtrés avec `jq` ont donné le message exact et une piste (`hint`).
- La base n'a pas été touchée : aucune donnée perdue ; correction sans redéploiement d'image.
- Le mail `[RESOLVED]` a confirmé le retour à la normale sans vérification manuelle.

### Ce qui a moins bien fonctionné
- La configuration est la cause, pas l'image : un rollback de version n'aurait rien réparé.
- L'API démarre en production avec une valeur par défaut de développement (`localhost`) au lieu de refuser.
- Deux mails ont été reçus : `TaskFlowMetricsDown` (warning) est parti 15 s avant `TaskFlowApiDown` (critical),
  donc avant que la règle d'inhibition puisse le masquer.
- Le message d'erreur dit `ECONNREFUSED` sans indiquer l'adresse utilisée, ce qui oblige à inspecter le conteneur.

### Actions
| Action | Type | Issue | Statut |
| --- | --- | --- | --- |
| En production (`APP_ENV=production`), l'API refuse de démarrer si `DATABASE_URL` est absente, avec un message explicite ; test dans `tests/config.test.js` | prévention | [#30](https://github.com/emidesa/taskflow/issues/30) | à faire |
| `deploy.sh` compare les noms de variables de `.env` et de `.env.example` et s'arrête s'il en manque une | prévention | - | à faire |
| Ajouter à `TaskFlowMetricsDown` un délai plus long que `TaskFlowApiDown` pour que l'inhibition s'applique | détection | - | à faire |
