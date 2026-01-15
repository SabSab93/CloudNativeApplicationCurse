# PLAN_BLUE_GREEN.md  
## Stratégie de déploiement Blue/Green

---

## 🎯 Objectifs pédagogiques

Ce document décrit la **stratégie de déploiement Blue/Green** mise en place pour le projet.  
L’objectif est de permettre le déploiement d’une nouvelle version de l’application **sans interruption de service**, tout en garantissant un **rollback rapide et fiable**.

Les compétences visées sont :
- Déploiement automatisé (CD)
- Mise en œuvre d’une stratégie Blue/Green
- Utilisation d’un reverse proxy
- Idempotence et maîtrise des environnements Docker

---

## 🧱 Architecture générale

L’architecture repose sur les composants suivants :

- **Deux versions applicatives** :
  - `blue` : version actuellement exposée aux utilisateurs
  - `green` : version candidate pour le prochain déploiement
- **Un reverse proxy Nginx** servant de point d’entrée unique
- **Une base de données PostgreSQL unique**, partagée par les deux versions
- **Docker Compose** pour l’orchestration locale
- **CI/CD GitHub Actions** avec runner self-hosted

---

## 📦 Organisation des fichiers Docker Compose

La stack est volontairement découpée afin de séparer :
- l’infrastructure partagée
- les instances applicatives versionnées

### Fichiers utilisés

- `docker-compose.base.yml`
  - PostgreSQL
  - Reverse proxy Nginx
  - Réseau Docker commun

- `docker-compose.blue.yml`
  - Backend version **blue**

- `docker-compose.green.yml`
  - Backend version **green**

Ce découpage permet de déployer une nouvelle version **sans impacter** celle actuellement en production.

---

## 🚀 Lancement de la stack

### Démarrage de la version active (exemple : blue)

```bash
docker compose -f docker-compose.base.yml -f docker-compose.blue.yml up -d
```

### Déploiement de la version candidate (green)

```bash
docker compose -f docker-compose.base.yml -f docker-compose.green.yml up -d
```

Les deux versions peuvent ainsi coexister simultanément.

---

## 🌐 Reverse Proxy et routage

### Rôle du reverse proxy

Le reverse proxy **Nginx** :
- écoute sur le port public (`http://localhost:8080`)
- redirige dynamiquement le trafic vers la version active

La version active est définie dans le fichier :

```
nginx/conf.d/active.conf
```

Exemple :

```nginx
set $upstream app-back-blue:3000;
```

### Bascule de version

La bascule s’effectue en modifiant `active.conf`, puis en rechargeant Nginx :

```bash
docker exec reverse-proxy nginx -s reload
```

Aucun conteneur applicatif n’est redémarré lors de cette opération.

---

## ❤️ Health Check et validation

Un endpoint `/health` est exposé par le backend.  
Il retourne notamment :

- `status`
- `timestamp`
- `color` (blue / green)
- `version` (tag de l’image Docker)

Ce endpoint est utilisé pour :
- vérifier la version active
- démontrer l’absence de coupure lors de la bascule
- faciliter le diagnostic et le rollback

---

## 🔁 Scénario de déploiement Blue/Green

1. La version **blue** est active et reçoit le trafic
2. Une nouvelle image Docker est construite et poussée par la CI
3. La version **green** est déployée en parallèle
4. Des vérifications fonctionnelles sont effectuées
5. Le reverse proxy est basculé vers **green**
6. En cas de problème, retour immédiat vers **blue**

---

## 🧪 Preuve de non-interruption de service

Une boucle de requêtes continue est utilisée pour simuler le trafic utilisateur :

```bash
while true; do
  curl http://localhost:8080/health
  sleep 0.2
done
```

Lors de la bascule :
- aucune requête ne retourne d’erreur
- le champ `color` change dynamiquement

Cela démontre un **déploiement sans downtime**.

---

## ⚙️ Intégration CI/CD

- Les images Docker sont :
  - construites par GitHub Actions
  - poussées vers **GitHub Container Registry (GHCR)**
  - taggées avec le **SHA du commit Git**
- La stratégie Blue/Green est déclenchée automatiquement sur la branche `develop`
- Un déploiement classique est conservé sur la branche `main`

---

## 🔄 Rollback

Le rollback est **quasi instantané** :
- il consiste à rétablir l’ancienne valeur de `active.conf`
- puis à recharger Nginx

Aucune reconstruction ni redéploiement n’est nécessaire.

---

## ✅ Conclusion

Cette stratégie Blue/Green permet :
- un déploiement sécurisé
- une absence de coupure côté utilisateur
- une mise en production contrôlée
- un rollback simple et rapide

Elle constitue une approche proche des environnements de production modernes et répond pleinement aux objectifs pédagogiques du TP.
