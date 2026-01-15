# TP6 — Monitoring & Observabilité d’une application conteneurisée (NestJS / Vue / Postgres)

> **Objectif du document** : expliquer clairement (niveau master) les concepts de monitoring/observabilité et le rôle de **Prometheus, Grafana, Loki, Promtail**, ainsi que l’intégration dans une stack Docker (avec blue/green côté applicatif).

---

## 1) Monitoring vs Observabilité (concepts clés)

### 1.1 Monitoring
Le **monitoring** consiste à **mesurer** l’état d’un système (disponibilité, performance, ressources) et à **déclencher des alertes** lorsqu’un indicateur sort d’un comportement normal.

- Approche souvent **orientée “symptômes”** : CPU > 80%, latence > 500ms, erreurs 5xx, etc.
- Très efficace pour : **détection** et **réaction** rapide (SRE / exploitation).
- Limite : on observe ce qu’on a **déjà prévu de mesurer**.

### 1.2 Observabilité
L’**observabilité** est la capacité à **comprendre l’état interne d’un système** à partir de ses signaux externes, notamment lors d’incidents non anticipés.

- Approche **orientée “diagnostic”** : comprendre *pourquoi* ça se dégrade, *où* ça casse, *quels services* sont impliqués.
- Repose sur des signaux riches et corrélables : métriques + logs + traces.
- Objectif : réduire le **MTTR** (Mean Time To Recovery) et améliorer la fiabilité.

### 1.3 Les 3 piliers
1) **Métriques** : séries temporelles numériques (latence, taux d’erreur, QPS, CPU…)
2) **Logs** : événements textuels structurés (requêtes, erreurs, contexte)
3) **Traces** : parcours d’une requête à travers plusieurs services (non demandé ici, mais à connaître)

Dans ce TP6, on met en place **métriques + logs** (traces optionnelles ultérieurement via OpenTelemetry).

---

## 2) Rôle des composants (stack open-source)

### 2.1 Prometheus (métriques)
**Prometheus** est un moteur de collecte et de stockage de métriques (time-series).

- Mode **pull** : Prometheus “scrape” des endpoints HTTP `/metrics`.
- Stockage local (TSDB) et requêtage via **PromQL**.
- Points forts :
  - modèle simple et robuste,
  - intégration native avec l’écosystème cloud-native,
  - compatible Kubernetes, Docker, exporters.

**Dans notre stack** :
- Prometheus collecte :
  - métriques **NestJS** (endpoint `/metrics`)
  - métriques système / Docker via exporters (ex : `cadvisor`, `node-exporter` — si ajoutés)
  - éventuellement métriques Nginx (proxy) si instrumenté.

### 2.2 Grafana (visualisation)
**Grafana** est l’interface de visualisation et d’analyse.

- Connexion à des sources : Prometheus (métriques), Loki (logs), etc.
- Construction de dashboards : latence, erreurs, throughput, disponibilité, saturation.
- Aide à :
  - observer des tendances,
  - diagnostiquer des incidents,
  - partager un état “prod-like” de manière lisible.

**Dans notre stack** :
- Grafana lit Prometheus (métriques) et Loki (logs).
- On construit des dashboards “application” + “infra” :
  - erreurs HTTP, latence p95/p99, requêtes/s, DB health,
  - CPU/Mem conteneurs, redémarrages, saturation.

### 2.3 Loki (logs)
**Loki** est un système de logs inspiré de Prometheus.

- Loki indexe principalement les **labels** (pas tout le contenu des logs), ce qui le rend :
  - plus économique,
  - plus simple à opérer.
- Le contenu des logs est stocké et requêté via **LogQL**.
- Excellent pour corréler :
  - un pic d’erreurs (métriques) → les logs associés (Loki).

**Dans notre stack** :
- Loki reçoit les logs de :
  - backend NestJS (stdout/stderr)
  - reverse-proxy Nginx (si logué vers stdout)
  - éventuellement Postgres (selon config)

### 2.4 Promtail (collecteur de logs)
**Promtail** collecte les logs et les envoie à Loki.

- Il “tail” :
  - des fichiers,
  - ou des sources Docker (selon la méthode de collecte).
- Il ajoute des **labels** utiles : `container`, `service`, `env`, `color` (blue/green), etc.
- Filtrage / parsing possible : JSON, regex, ajout de champs.

**Dans notre stack** :
- Promtail envoie vers Loki les logs des conteneurs.
- On étiquette les logs pour distinguer :
  - `app-back-blue` vs `app-back-green`,
  - environnements (dev/main),
  - services (proxy, db, backend).

---

## 3) Architecture globale (schéma)

### 3.1 Schéma ASCII (stack complète)

```
                     ┌──────────────────────────────┐
                     │          Utilisateur          │
                     └───────────────┬──────────────┘
                                     │
                                     ▼
                         ┌──────────────────────┐
                         │   Reverse Proxy      │
                         │        Nginx         │
                         └─────────┬────────────┘
                                   │ route vers blue OU green
              ┌────────────────────┴────────────────────┐
              ▼                                         ▼
   ┌──────────────────────┐                  ┌──────────────────────┐
   │  Backend BLUE         │                  │  Backend GREEN        │
   │  (NestJS)             │                  │  (NestJS)             │
   │  /health  /metrics    │                  │  /health  /metrics    │
   └───────────┬──────────┘                  └───────────┬──────────┘
               │                                         │
               └──────────────┬──────────────────────────┘
                              ▼
                    ┌───────────────────┐
                    │   PostgreSQL      │
                    │ (DB unique partagée)│
                    └───────────────────┘


      ┌────────────────────────── Monitoring Stack ──────────────────────────┐
      │                                                                       │
      │   ┌───────────────┐        PromQL        ┌────────────────────────┐  │
      │   │  Prometheus    │<--------------------│        Grafana          │  │
      │   │ (scrape /metrics)│                    │ (dashboards + queries) │  │
      │   └───────▲────────┘                     └──────────▲─────────────┘  │
      │           │                                          │ LogQL          │
      │           │ scrape                                   │                │
      │   ┌───────┴────────┐                                │                │
      │   │  Backend metrics │                                │                │
      │   └─────────────────┘                       ┌────────┴───────────┐   │
      │                                              │        Loki         │   │
      │                                              │ (logs storage/query)│   │
      │                                              └────────▲───────────┘   │
      │                                                       │ push           │
      │                                              ┌────────┴───────────┐   │
      │                                              │      Promtail       │   │
      │                                              │ (collect logs)      │   │
      │                                              └────────────────────┘   │
      └───────────────────────────────────────────────────────────────────────┘
```

---

## 4) Intégration de l’application dans la stack

### 4.1 Exposer des métriques NestJS
On ajoute un module Prometheus au backend (NestJS), via `@willsoto/nestjs-prometheus` (ou équivalent).

- L’application expose un endpoint `/metrics`
- Prometheus scrape ce endpoint à intervalle régulier (ex : toutes les 10s)
- On obtient :
  - métriques Node.js (event loop, mémoire)
  - métriques HTTP (si activées/ajoutées)
  - métriques custom (compteurs, histogrammes)

**Exemples de métriques utiles** :
- `http_requests_total{method,route,status}`
- `http_request_duration_seconds_bucket{route}`
- `process_resident_memory_bytes`
- `nodejs_eventloop_lag_seconds`

### 4.2 Collecter des métriques Docker / système
Pour avoir une observabilité “infra”, on ajoute souvent :
- **cAdvisor** : métriques conteneurs (CPU, RAM, I/O, réseau)
- **node-exporter** : métriques machine hôte (optionnel en local)

Ce TP recommande Docker, donc cAdvisor est très pertinent.

### 4.3 Centraliser les logs
Les services doivent loguer vers **stdout/stderr** (bonne pratique conteneur).

- Backend : logs NestJS (idéalement en JSON)
- Proxy : logs Nginx configurés vers stdout
- DB : logs Postgres (optionnel)

Promtail collecte et étiquette :
- `service="backend"`, `color="blue"` / `color="green"`, `container=...`

Puis Grafana permet :
- recherche d’erreurs,
- corrélation avec un pic de latence.

---

## 5) Ports d’exécution (local)

Ces ports sont typiquement utilisés (peuvent être adaptés selon votre compose) :

- **Grafana** : `http://localhost:3001` (ou 3000 si libre)
- **Prometheus** : `http://localhost:9090`
- **Loki** : `http://localhost:3100`
- **Promtail** : pas forcément exposé (agent)
- **cAdvisor** (si utilisé) : `http://localhost:8081` (optionnel)

> **Note** : dans votre projet, `8080` est déjà utilisé par le reverse-proxy applicatif.  
> On évite donc de réutiliser `3000` si Grafana entre en conflit avec l’API backend ; on choisit `3001` pour Grafana.

---

## 6) Conclusion (résultat attendu TP6)

À la fin du TP6, l’application doit devenir “observable” :

- **Métriques** : Prometheus scrape `/metrics` du backend + métriques conteneurs
- **Logs** : Loki centralise les logs, Promtail les collecte
- **Dashboards** : Grafana visualise l’état applicatif + infra

Cela permet :
- de détecter une dégradation (monitoring),
- et d’en comprendre la cause (observabilité).

---

## Annexes — Suggestions de dashboards Grafana (niveau pro)

### A) Dashboard “Application (NestJS)”
- Taux de requêtes (RPS)
- Taux d’erreurs (4xx/5xx)
- Latence p50/p95/p99
- Top routes les plus lentes
- Redémarrages conteneur backend
- Comparaison blue vs green (si labels `color`)

### B) Dashboard “Infra (Docker)”
- CPU / RAM par conteneur (blue vs green)
- I/O disque (Postgres)
- Réseau entrant/sortant
- Disponibilité des services (`up`)

### C) Dashboard “Logs”
- erreurs par minute
- top messages d’erreur
- logs filtrés par `color=green` lors d’un déploiement
- corrélation logs ↔ pic d’erreurs/latence
