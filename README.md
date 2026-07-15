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

> Variante « images publiées » : dans `docker-compose.yml`, remplacer `build:` par
> `image: ghcr.io/<owner>/microcrm-<cible>:<tag>` pour tourner à partir des images GHCR
> produites par la CI.

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

À chaque `push` et chaque _Pull Request_ vers `main` :

1. **`backend-ci`** — build et tests du backend (`./gradlew build`) sur JDK 21 (Temurin), avec cache Gradle ;
2. **`frontend-ci`** — installation reproductible (`npm ci`), tests unitaires Chrome headless avec couverture, puis build de production Angular, avec cache npm.

Uniquement sur `push` vers `main` ou sur un tag `v*`, et **seulement si les tests passent** (_quality gate_) :

3. **`docker`** — build des images `front`, `back` et `standalone` (Buildx + cache) et publication sur le **GitHub Container Registry** (`ghcr.io`).

Les mises à jour de dépendances (Gradle, npm, Docker, GitHub Actions) sont automatisées via [Dependabot](./.github/dependabot.yml).
