<p align="center">
   <img src="./front/src/favicon.png" width="192px" />
</p>

# MicroCRM (P7 - Développeur Full-Stack - Java et Angular - Mettez en œuvre l'intégration et le déploiement continu d'une application Full-Stack)

MicroCRM est une application de démonstration basique ayant pour être objectif de servir de socle pour le module "P7 - Développeur Full-Stack".

L'application MicroCRM est une implémentation simplifiée d'un ["CRM" (Customer Relationship Management)](https://fr.wikipedia.org/wiki/Gestion_de_la_relation_client). Les fonctionnalités sont limitées à la création, édition et la visualisations des individus liés à des organisations.

![Page d'accueil](./misc/screenshots/screenshot_1.png)
![Édition de la fiche d'un individu](./misc/screenshots/screenshot_2.png)

## Code source

### Organisation

Ce [monorepo](https://en.wikipedia.org/wiki/Monorepo) contient les 2 composantes du projet "MicroCRM":

- La partie serveur (ou "backend"), en Java (JDK 21) avec Spring Boot 3.5;
- La partie cliente (ou "frontend"), en Angular 20.

### Démarrer avec les sources

#### Serveur

##### Dépendances

- [OpenJDK >= 21](https://openjdk.org/)

##### Procédure

1. Se positionner dans le répertoire `back` avec une invite de commande:

   ```shell
   cd back
   ```

2. Construire le JAR:

   ```shell
   # Sur Linux
   ./gradlew build

   # Sur Windows
   gradlew.bat build
   ```

3. Démarrer le service:

   ```shell
   java -jar build/libs/microcrm-0.0.1-SNAPSHOT.jar
   ```

Puis ouvrir l'URL http://localhost:8080 dans votre navigateur.

#### Client

##### Dépendances

- [Node.js >= 22 (LTS)](https://nodejs.org/) et NPM >= 10

##### Procédure

1. Se positionner dans le répertoire `front` avec une invite de commande:

   ```shell
   cd front
   ```

2. (La première fois seulement) Installer les dépendances NodeJS:

   ```shell
   npm install
   ```

3. Démarrer le service de développement:

   ```shell
   npx @angular/cli serve
   ```

Puis ouvrir l'URL http://localhost:4200 dans votre navigateur.

### Exécution des tests

#### Client

**Dépendances**

- Google Chrome ou Chromium

Dans votre terminal:

```shell
cd front
CHROME_BIN=</path/to/google/chrome> npm test
```

#### Serveur

Dans votre terminal:

```shell
cd back
./gradlew test
```

### Démarrer avec Docker Compose (recommandé)

La façon la plus simple de lancer l'application complète (front + back) sans installer Java
ni Node :

```shell
docker compose up --build
```

- Frontend : http://localhost:4200
- API : http://localhost:8080

Compose construit les mêmes cibles (`front`, `back`) que la CI, démarre le back puis le
front une fois le back *healthy* (healthchecks), et publie le back sur le port `8080`
(requis : le front appelle l'API en absolu via `front/src/app/config.ts`). Arrêt :
`docker compose down`.

> **Variante « images publiées »** : pour exécuter une release **déjà publiée** sur GHCR au
> lieu de reconstruire localement, superposer [`docker-compose.deploy.yml`](./docker-compose.deploy.yml),
> qui ne redéfinit que l'origine des images (ports, healthchecks et réseau restent ceux de
> `docker-compose.yml`) :
>
> ```shell
> export GHCR_OWNER=smniuc IMAGE_TAG=latest   # ou un tag immuable : sha-1a2b3c4
> docker compose -f docker-compose.yml -f docker-compose.deploy.yml pull
> docker compose -f docker-compose.yml -f docker-compose.deploy.yml up -d --no-build --wait
> ```
>
> C'est exactement la séquence exécutée par le job `deploy` du pipeline (voir plus bas), ce
> qui permet de **rejouer localement, à l'identique, n'importe quelle release**.

### Images Docker (construction/exécution unitaire)

#### Client

##### Construire l'image

```shell
docker build --target front -t orion-microcrm-front:latest .
```

##### Exécuter l'image

```shell
docker run -it --rm -p 4200:80 orion-microcrm-front:latest
```

L'application sera disponible sur http://localhost:4200. (Le conteneur sert du HTTP simple
sur le port 80 ; la terminaison TLS est déléguée à un reverse-proxy en amont.)

#### Serveur

##### Construire l'image

```shell
docker build --target back -t orion-microcrm-back:latest .
```

##### Exécuter l'image

```shell
docker run -it --rm -p 8080:8080 orion-microcrm-back:latest
```

L'API sera disponible sur http://localhost:8080.

#### Tout en un

```shell
docker build --target standalone -t orion-microcrm-standalone:latest .
```

##### Exécuter l'image

```shell
docker run -it --rm -p 8080:8080 -p 4200:80 orion-microcrm-standalone:latest
```

L'application sera disponible sur http://localhost:4200 et l'API sur http://localhost:8080.

## Intégration et déploiement continus (CI/CD)

Le pipeline est défini dans [`.github/workflows/ci-cd.yml`](./.github/workflows/ci-cd.yml) (GitHub Actions).

### Vue d'ensemble

À chaque `push` et chaque _Pull Request_ vers `main` :

1. **`backend-ci`** — build et tests du backend (`./gradlew build jacocoTestReport`) sur JDK 21 (Temurin), avec cache Gradle. Publie les classes compilées et le rapport de couverture JaCoCo en artefacts ;
2. **`frontend-ci`** — installation reproductible (`npm ci`), tests unitaires Chrome headless avec couverture LCOV, puis build de production Angular, avec cache npm ;
3. **`sonar`** — analyse qualité & sécurité (SAST) du monorepo sur **SonarQube Cloud**. S'exécute après les tests, dont il **réutilise les artefacts** (pas de recompilation, tests joués une seule fois). Le _Quality Gate_ est **bloquant** (`sonar.qualitygate.wait=true`).

Uniquement sur `push` vers `main` ou sur un tag `v*`, et seulement si les tests **et** l'analyse Sonar passent :

4. **`docker`** — build des images `front`, `back` et `standalone` (Buildx + cache) et publication sur le **GitHub Container Registry** (`ghcr.io`) ;
5. **`deploy`** — démarre les images **publiées**, vérifie qu'elles répondent (_smoke tests_), puis promeut le tag `latest`.

### Le déploiement (CD) en détail

**La cible de livraison est le registre GHCR** : « déployer » signifie ici publier un artefact conteneurisé **versionné et vérifié**, immédiatement exécutable par un tiers (`docker compose … up`). Ce choix suit l'option « publication des images Docker » de l'énoncé et évite d'introduire une plateforme d'hébergement externe — donc un compte, des secrets et une complexité qui n'apporteraient rien au périmètre du projet.

Le modèle est **« publier → vérifier → promouvoir »** :

| Tag | Nature | Posé par | Signification |
|-----|--------|----------|---------------|
| `sha-<court>` | **immuable** | `docker` | Une build donnée, tracée jusqu'au commit exact. Ne bouge jamais. |
| `v1.2.3`, `v1.2` | **immuable** | `docker` | Version sémantique, sur les tags `v*` uniquement. |
| `latest` | **mobile** | `deploy` | Dernière release de `main` **dont on a vérifié qu'elle démarre**. |

Le point important : `latest` n'est **pas** posé au moment du build. Le job `deploy` récupère l'image immuable qui vient d'être publiée, la démarre réellement, et ne déplace `latest` que si les smoke tests passent. La promotion se fait par re-étiquetage **côté registre** (`docker buildx imagetools create`), sans reconstruction : l'image promue est bit-pour-bit celle qui a été testée. `latest` est donc toujours une version vérifiée, et un échec de vérification laisse `latest` sur la dernière release saine.

Ce que vérifient les smoke tests — l'artefact **livré**, pas une recompilation :

- les conteneurs `front` et `back` atteignent l'état `healthy` (`--wait` s'appuie sur les `HEALTHCHECK` du `Dockerfile`) ;
- le front sert bien l'application (l'`index.html` servi contient `<app-root>`) ;
- l'API répond, et `/organizations` **expose « Orion Incorporated »** — soit un comportement métier réel (Spring Data REST + chargement des fixtures), pas un simple code HTTP 200 ;
- l'image `standalone`, absente de la compose, est vérifiée séparément sur des ports dédiés.

**Traçabilité et métriques** : le job est rattaché à l'environnement GitHub `release`, qui enregistre chaque livraison (date, commit, auteur). Cet historique est la source des métriques **DORA** (fréquence de déploiement, _lead time for changes_) exploitées en Partie 2.

**Sécurité** : le pipeline n'utilise **aucun identifiant en clair**. Le job `deploy` s'authentifie sur GHCR avec le `GITHUB_TOKEN` fourni automatiquement par GitHub — restreint à ce dépôt, limité aux permissions déclarées (`packages: write`) et expiré à la fin du job. Le seul secret du dépôt est `SONAR_TOKEN`. L'application ne manipule aucune donnée sensible (base HSQLDB **en mémoire**, aucun identifiant à injecter).

### Commandes clés du pipeline

Pour chaque commande importante : son objectif, où elle est définie, et à quel moment elle s'exécute.

| Commande | Objectif | Définie dans | Exécutée |
|----------|----------|--------------|----------|
| `./gradlew build jacocoTestReport` | Compiler le back, jouer les tests JUnit et produire la couverture JaCoCo (XML lu par Sonar) | `back/build.gradle` (plugin `jacoco`, `test.finalizedBy jacocoTestReport`) | **CI** — job `backend-ci`, à chaque push/PR |
| `npm ci` | Installer les dépendances front **à l'identique du lock** (reproductible, contrairement à `npm install`) | `front/package-lock.json` | **CI** — job `frontend-ci`, avant les tests ; **local** |
| `npm run test:ci` | Lancer tous les tests front en Chrome headless, une seule passe, avec couverture LCOV | `front/package.json` (script `test:ci`), `front/karma.conf.js` (reporter `lcovonly`) | **CI** — job `frontend-ci`, après `npm ci` |
| `npm run build` | Produire le bundle Angular de production | `front/package.json` | **CI** — job `frontend-ci` ; **build d'image** (étage `front-build` du `Dockerfile`) |
| `sonarqube-scan-action` | Analyser qualité + sécurité et **bloquer** si le Quality Gate échoue | `.github/workflows/ci-cd.yml` (job `sonar`), `sonar-project.properties` | **CI** — après les tests, avant toute publication |
| `docker build --target <cible>` | Construire une image (`front`, `back`, `standalone`) depuis le `Dockerfile` multi-stage | `Dockerfile` | **Release** — job `docker` (via `build-push-action`) ; **local** |
| `docker compose up --build` | Lancer l'app complète en local depuis les sources | `docker-compose.yml` | **Local** |
| `docker compose -f … -f docker-compose.deploy.yml pull` | Récupérer les images **publiées** de la release à vérifier | `docker-compose.deploy.yml` | **Release** — job `deploy` ; **local** (rejouer une release) |
| `docker compose … up -d --no-build --wait` | Démarrer la release publiée et **attendre les healthchecks** (`--no-build` neutralise le `build:` hérité) | `docker-compose.yml` + `docker-compose.deploy.yml` | **Release** — job `deploy` ; **local** |
| `curl -fsS …` + `grep` | Smoke tests : le front sert l'app, l'API expose les données attendues | `.github/workflows/ci-cd.yml` (job `deploy`) | **Release** — job `deploy`, après le démarrage |
| `docker buildx imagetools create` | Promouvoir en `latest` l'image vérifiée, par re-étiquetage côté registre (sans rebuild) | `.github/workflows/ci-cd.yml` (job `deploy`) | **Release** — job `deploy`, sur `main`, **après** les smoke tests |

### Mises à jour de dépendances

Les mises à jour (Gradle, npm, Docker, GitHub Actions) sont automatisées via [Dependabot](./.github/dependabot.yml).
