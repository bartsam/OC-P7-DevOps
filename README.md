<p align="center">
   <img src="./front/src/favicon.png" width="192px" />
</p>

# MicroCRM

MicroCRM est une application de démonstration basique ayant pour objectif de servir de socle pour le module "P7 - Développeur Full-Stack - Java et Angular - Mettez en œuvre l'intégration et le déploiement continu d'une application Full-Stack".

L'application MicroCRM est une implémentation simplifiée d'un ["CRM" (Customer Relationship Management)](https://fr.wikipedia.org/wiki/Gestion_de_la_relation_client). Les fonctionnalités sont limitées à la création, l'édition et la visualisations des individus liés à des organisations.

![Page d'accueil](./misc/screenshots/screenshot_1.png)
![Édition de la fiche d'un individu](./misc/screenshots/screenshot_2.png)

## Livrables

| Livrable                | Emplacement                                                                                |
| ----------------------- | ------------------------------------------------------------------------------------------ |
| Workflow CI/CD          | [ci.yml](.github/workflows/ci.yml) et [release.yml](.github/workflows/release.yml)         |
| Conteneurisation        | [Dockerfile](Dockerfile), [docker-compose.yml](docker-compose.yml)                         |
| Monitoring local        | [docker-compose-with-elk.yml](docker-compose-with-elk.yml), [logstash.conf](logstash.conf) |
| Documentation technique | [documentation-technique.md](docs/documentation-technique.md)                              |
| Captures d'écran        | [docs/screenshots](docs/screenshots/)                                                      |

## Stack et prérequis

Le monorepo réunit une API Java 17 / Spring Boot 3 et un front Angular 17.

- Java 17 ;
- Node.js 20 et npm ;
- Google Chrome ou Chromium pour les tests Angular ;
- Docker Desktop, ou Docker Engine avec le plugin Compose.

## Choix techniques CI/CD

- **GitHub Actions** automatise les tests, les builds, l’analyse SonarQube et la publication des images.
- **SonarQube Cloud** analyse la qualité et la sécurité du code ; le Quality Gate conditionne la publication.
- **Docker multi-stage** produit des images front-end et back-end distinctes, légères et reproductibles.
- **GitHub Container Registry (GHCR)** publie les images validées avec les tags `latest` et SHA du commit.
- **GitHub Releases** archive le JAR Spring Boot et le bundle Angular pour chaque tag `vX.Y.Z`.
- **ELK** centralise localement les logs applicatifs et HTTP pour le monitoring.

## Code source

### Organisation

Ce [monorepo](https://en.wikipedia.org/wiki/Monorepo) contient les 2 composantes du projet "MicroCRM":

- La partie serveur (ou "backend"), en Java SpringBoot 3;
- La partie cliente (ou "frontend"), en Angular 17.

### Démarrer avec les sources

#### Serveur

##### Dépendances

- [OpenJDK >= 17](https://openjdk.org/)

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

- [NPM >= 10.2.4](https://www.npmjs.com/)

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

##### Dépendances

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

#### Script

Depuis la racine du dépôt, le script `run-tests.sh` utilisé par la CI exécute les tests front
et back et centralise les rapports JUnit dans `test-results/` :

```shell
CHROME_BIN=/chemin/vers/google-chrome bash ./run-tests.sh
```

## Images Docker

Le `Dockerfile` est multi-stage afin de séparer la construction de l’exécution :

- Angular est compilé avec Node.js puis servi par Caddy ;
- Spring Boot est compilé avec Gradle puis exécuté avec une JRE Temurin (avec un utilisateur non-root);
- les images finales n’embarquent pas les outils de build, ce qui réduit leur taille et leur surface d’attaque ;

Les deux cibles peuvent être construites séparément :

```shell
docker build --target front -t microcrm-front:local .
docker build --target back -t microcrm-back:local .
```

## Docker Compose

Le fichier `docker-compose.yml` orchestre les images locales `microcrm-front:local` et `microcrm-back:local`.
Le front attend que le healthcheck HTTP du back-end soit sain avant de démarrer.
Puis Caddy sert les fichiers Angular et relaie les requêtes `/api/*` vers le service `back`.

L’environnement local utilise HTTP. Une configuration HTTPS nécessite un nom de
domaine et une configuration de déploiement adaptée. Ces images locales sont
distinctes des images publiées dans GHCR par la CI.

##### Dépendances

- Docker Desktop (ou Docker Engine et le plugin Compose)

##### Procédure

Depuis la racine du dépôt :

```shell
docker compose up -d --build
docker compose ps
```

Lorsque les services sont `healthy` :

- le front est accessible sur http://localhost ;
- l’API est disponible sur http://localhost:8080.

Pour arrêter l’environnement :

```shell
docker compose down
```

## CI/CD

### Workflow

Le workflow principal, défini dans [ci.yml](.github/workflows/ci.yml),
s’exécute sur les pull requests et les pushs vers `main`, il enchaîne :

1. les **tests** Angular et Spring Boot, avec publication des rapports JUnit et de couverture ;
2. les **builds** front-end et back-end, puis la validation de Compose ;
3. l’analyse **SonarQube** et le Quality Gate ;
4. sur un push vers `main` uniquement, la construction et la **publication des
   images** Docker dans GitHub Container Registry (GHCR).

Un échec des tests, du build ou du Quality Gate empêche la publication des
images. Le secret GitHub Actions `SONAR_TOKEN` est requis pour l’analyse
SonarQube et ne doit jamais être versionné.

Les images publiées sont :

```text
ghcr.io/<owner>/microcrm-front:latest
ghcr.io/<owner>/microcrm-back:latest
```

Chaque image reçoit également un tag correspondant au SHA du commit. Ce tag
immuable permet d’identifier une version validée et d’effectuer un retour à une
version antérieure. Le fichier Compose local ne consomme pas directement ces
images GHCR.

### Release

Le workflow de release, défini dans [release.yml](.github/workflows/release.yml),
s’exécute à partir d’un tag SemVer :

```shell
git tag vX.Y.Z
git push origin vX.Y.Z
```

Le workflow produit alors l’archive Angular, le JAR Spring Boot et la GitHub
Release associée.

## Monitoring local

La stack ELK est destinée à l’observation locale. Les logs JSON de Spring Boot
et les logs HTTP de Caddy sont envoyés à Logstash, indexés dans Elasticsearch,
puis consultables dans Kibana.

Pour démarrer l'application avec la stack ELK en une seule commande :

```shell
docker compose -f docker-compose-with-elk.yml up -d --build
```

| Service       | Adresse               |
| ------------- | --------------------- |
| Application   | http://localhost      |
| API           | http://localhost:8080 |
| Kibana        | http://localhost:5601 |
| Elasticsearch | http://localhost:9200 |

Pour consulter les logs dans Kibana :

1. Ouvrez http://localhost:5601, puis accédez à **Stack Management** → **Data Views**.
2. Sélectionnez **Create data view** et saisissez `microcrm-logs-*` comme modèle d’index.
3. Sélectionnez `@timestamp` comme champ temporel, puis enregistrez le _data view_.
4. Ouvrez **Discover**, sélectionnez ce _data view_ et actualisez la liste après avoir généré du trafic sur l’application :
   - `curl http://localhost/api/organizations`
   - `curl http://localhost/api/persons`

Pour arrêter l’environnement :

```shell
docker compose -f docker-compose-with-elk.yml down
```

## Documentation

La [documentation technique](docs/documentation-technique.md) détaille le
pipeline, les plans de tests, de sécurité, de sauvegarde et de mise à jour,
ainsi que les métriques DORA et les KPI.
