# Documentation Technique - ORION - MicroCRM

## 1. Introduction

### 1.1 Contexte

Orion souhaite fiabiliser la livraison de **MicroCRM**, une application interne de gestion de la relation client destinée aux services technique et commercial. Elle permet de consulter, créer et modifier des personnes ainsi que les organisations auxquelles elles sont rattachées.

Le projet est organisé en monorepo Git. Il réunit un front-end développé avec Angular 17, TypeScript et RxJS, dont les tests unitaires s’appuient sur Jasmine et Karma, ainsi qu’une API REST développée en Java 17 avec Spring Boot 3.2.5 et Gradle. Les tests du back-end reposent sur JUnit et les données sont actuellement stockées dans une base HSQLDB embarquée.

Avant l’industrialisation, la construction, les tests et la livraison reposaient principalement sur des actions manuelles. L’[audit initial](01-audit.md) a également mis en évidence les limites de la conteneurisation existante : versions d’exécution non alignées, port exposé incohérent avec l’API, image `standalone` regroupant plusieurs processus et recours à des images génériques. Ces écarts augmentaient le risque d’erreur, allongeaient les délais de livraison et compliquaient la reproduction d’un environnement fonctionnel.

### 1.2 Objectifs

L’objectif est donc d’automatiser les contrôles nécessaires avant la mise à disposition d’une version, afin de rendre la chaîne de livraison reproductible, de réduire le risque de régression et de produire des indicateurs exploitables sur sa qualité, sa sécurité et son fonctionnement.

- Automatiser la construction, les tests et l’analyse de qualité à chaque pull request vers `main` et à chaque push sur cette branche.
- Produire des images Docker reproductibles pour le front-end et le back-end, puis les publier dans GitHub Container Registry (GHCR).
- Versionner les livrables par tag Git et publier les artefacts de release : archive Angular et JAR Spring Boot.
- Documenter les contrôles de sécurité, la stratégie de tests, la conteneurisation, la sauvegarde, les mises à jour et les indicateurs de suivi.
- Centraliser les logs dans un environnement ELK local afin d’observer les erreurs et les performances applicatives.

La publication des images et des artefacts constitue la mise à disposition d’une version. Le déploiement sur un environnement cible reste une opération distincte : l'hôte concerné peut récupérer les images identifiées par le SHA du commit puis les exécuter.

## 2. Étapes de mise en œuvre du pipeline CI/CD

### 2.1 Structure du pipeline

#### Déclencheurs et ordre d'exécution

Le workflow **MicroCRM Pipeline** est défini dans [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) :

- Il automatise les contrôles avant la publication des images de l'application.
- Il s'exécute lors d'une pull request vers main et lors d'un push sur main.
- Un push direct sur une autre branche ne déclenche pas les contrôles obligatoires qui sont concentrés sur les changements destinés à la branche principale.
- Un échec des tests, du build ou du Quality Gate empêche la publication des images.

Les jobs s'enchaînent ainsi :

|  Ordre   |    Job    | Rôle                                                                                                                                                      |
| :------: | :-------: | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
|    1     |  `tests`  | Exécute les tests Angular et Java, puis publie les rapports JUnit et de couverture.                                                                       |
|    2     |  `build`  | Construit le front et le back, puis valide la configuration Docker Compose.                                                                               |
|    3     |  `sonar`  | Télécharge les rapports de couverture, prépare les classes et bibliothèques Java, lance l’analyse SonarQube et vérifie le Quality Gate.                   |
|    4     | `docker`  | **Push sur `main` uniquement** : construit les images Docker `front` et `back`, puis les publie dans GitHub Container Registry (GHCR).                    |
| Distinct | `release` | **Workflow distinct — tag `vX.Y.Z` requis** : vérifie le tag, génère le ZIP Angular et le JAR Spring Boot, puis crée la GitHub Release avec ces fichiers. |

La capture de l'[exécution réussie du pipeline](screenshots/github-pipeline.png) montre l’enchaînement des jobs de tests, build, analyse SonarQube et publication des images Docker, ainsi que de la disponibilité des rapports et artefacts produits.

#### Politique de versioning

Les versions suivent SemVer (`MAJOR.MINOR.PATCH`). Aucune release candidate n'est créée par commit : chaque merge sur `main` publie des images Docker identifiées par SHA. Il n'y a pas de branche par release, car `main` est la seule branche de référence.
La création d'une version est une action humaine. Une fois la CI de main validée, un développeur pose le tag vX.Y.Z sur le commit concerné qui déclenche [`release.yml`](../.github/workflows/release.yml) :

1. vérifie que le tag respecte strictement le format vX.Y.Z ;
2. construit l'archive Angular et le JAR Spring Boot depuis le commit tagué ;
3. crée la GitHub Release avec ces artefacts.

La [release GitHub](screenshots/github-release.png) v0.1.0 illustre ce résultat. Les [packages GitHub Container Registry](screenshots/github-package.png) confirme la publication des images `microcrm-front` et `microcrm-back`, utilisées pour déployer une version validée de l’application.

#### Choix des actions GitHub

Les actions GitHub, Docker et SonarSource retenues sont officielles ou maintenues par leurs éditeurs. Elles limitent la dette de maintenance et facilitent le suivi des mises à jour. L'action communautaire `mikepenz/action-junit-report` complète ce socle en rendant les résultats de tests lisibles dans GitHub. Les caches npm, Gradle et GitHub Actions réduisent la durée des installations et des builds ; ils contribuent ainsi à réduire la part CI du Lead Time. La release automatisée assure la traçabilité des livrables binaires par leur tag SemVer.

| Action                                                                           | Rôle                                                                                                                                                                                             | Job(s) utilisant l'action                                                   |
| -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| `actions/checkout`                                                               | Récupère le dépôt. Le job SonarQube utilise `fetch-depth: 0` afin d'analyser l'historique complet.                                                                                               | `tests`, `build`, `sonar`, `docker` ; `release` dans le workflow de release |
| `actions/setup-node`                                                             | Installe Node.js 20 et active le cache npm, afin de réduire le temps d'installation des dépendances front.                                                                                       | `tests`, `build` ; `release`                                                |
| `actions/setup-java`                                                             | Installe Java 17 (distribution Temurin), active le cache Gradle, pour réduire le temps de préparation du back.                                                                                   | `tests`, `build`, `sonar` ; `release`                                       |
| `actions/upload-artifact`                                                        | Publie les rapports JUnit et de couverture sans les versionner dans Git.                                                                                                                         | `tests`                                                                     |
| `actions/download-artifact`                                                      | Rend les rapports de couverture disponibles pour l'analyse SonarQube.                                                                                                                            | `sonar`                                                                     |
| `mikepenz/action-junit-report`                                                   | Affiche les résultats JUnit dans les checks GitHub. Les fichiers bruts restent téléchargeables comme artefact.                                                                                   | `tests`                                                                     |
| `docker/login-action`, `docker/setup-buildx-action`, `docker/build-push-action`  | S'authentifient auprès de GHCR avec le token GitHub, construisent les cibles `front` et `back` du Dockerfile et exploitent Buildx et le cache GitHub Actions pour accélérer les builds d'images. | `docker`                                                                    |
| `SonarSource/sonarqube-scan-action`, `SonarSource/sonarqube-quality-gate-action` | Importent les résultats de qualité et bloquent la publication si le Quality Gate échoue.                                                                                                         | `sonar`                                                                     |
| `gh release create`                                                              | Crée une GitHub Release et y joint le JAR et l'archive Angular produits depuis le commit tagué, pour tracer les livrables par leur version SemVer.                                               | `release`                                                                   |

### 2.2 Scripts d'automatisation

| Commande ou fichier                                       | Rôle                                                                                         | Exécution      |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------------- | -------------- |
| [`run-tests.sh`](../run-tests.sh)                         | Exécute les tests front et back, puis centralise les rapports JUnit XML sous `test-results/` | Job `tests`    |
| `npm run test:coverage`                                   | Exécute Karma dans Chrome headless et génère les rapports de couverture LCOV                 | `run-tests.sh` |
| `./gradlew clean test`                                    | Lance les tests Spring Boot et génère le rapport JaCoCo.                                     | `run-tests.sh` |
| `npm run build`                                           | Génère les fichiers statiques Angular dans `front/dist/`                                     | Job `build`    |
| `./gradlew build`                                         | Tests, compile et package l’API dans un JAR exécutable.                                      | Job `build`    |
| `docker compose config -q`                                | Valide la configuration Compose et résout ses variables.                                     | Job `build`    |
| [`sonar-project.properties`](../sonar-project.properties) | Déclare les sources, tests, binaires Java et chemins de couverture importés par SonarQube.   | Job `sonar`    |

En local, les tests sont lancés depuis la racine avec `CHROME_BIN=/chemin/vers/google-chrome bash ./run-tests.sh`. Node.js 20, Java 17 et Chrome ou Chromium sont requis. Toute modification d'une commande de test ou d'un chemin de rapport doit être répercutée dans `run-tests.sh`, le workflow et `sonar-project.properties`.

### 2.3 Reproductibilité

Les éléments suivants assurent des builds cohérents en local et dans GitHub Actions :

- Les versions Node.js 20 et Java 17 sont fixées dans les variables du workflow,
- `npm ci` installe les versions verrouillées dans front/package-lock.json,
- Gradle Wrapper fixe la version Gradle 8.7 pour le back-end,
- `Dockerfile` utilise des stages dédiés et des tags d’images de base explicites,
- Les images publiées dans GHCR reçoivent un tag `latest` et un tag `SHA` qui identifie le commit construit et qui est préférable pour déployer une version.

#### Relancer le pipeline

Le pipeline est relancé automatiquement après une nouvelle mise à jour de pull request ou un push sur main. Une exécution existante peut également être relancée depuis l'onglet Actions de GitHub.

#### Gestion des secrets

Les secrets ne sont pas versionnés dans le dépôt et sont masqués dans GitHub Actions :

- `SONAR_TOKEN` est stocké dans les GitHub Actions Secrets et n'est transmis qu'aux étapes SonarQube.
- `GITHUB_TOKEN` fourni temporairement par GitHub Actions, est utilisé avec les permissions minimales nécessaires pour publier les packages et les releases.
- Les variables non sensibles, comme `CADDY_SITE_ADDRESS`, peuvent être placées dans un fichier non versionné .env créé à partir de .env.example.
- Toute donnée sensible doit être ajoutée au gestionnaire de secrets de GitHub ou de l'environnement cible, jamais au dépôt, aux images ou aux journaux.

## 3. Plan de conteneurisation et de déploiement

La conteneurisation de MicroCRM réunit le frontend Angular et l’API Spring Boot dans un environnement homogène et reproductible. La base HSQLDB est embarquée dans l’application backend : aucun service de base de données distinct n’est nécessaire.

### 3.1 Dockerfiles

#### Principaux choix techniques

Le [`Dockerfile`](../Dockerfile), placé à la racine du dépôt, produit deux images d'exécution indépendantes : `front` pour l'application Angular et `back` pour l'API Spring Boot. Elles s'appuient sur leurs stages de build respectifs (`front-build` et `back-build`) pour générer les artefacts nécessaires à leur exécution.

#### Multi-stage build et optimisations

| Stage         | Image de base            | Rôle                                                                | Résultat                                        |
| ------------- | ------------------------ | ------------------------------------------------------------------- | ----------------------------------------------- |
| `front-build` | `node:20-alpine`         | Installe les dépendances, puis construit Angular.                   | Bundle statique Angular pour les images finales |
| `back-build`  | `gradle:8.7-jdk17`       | Teste, compile et crée le JAR Spring Boot.                          | JAR exécutable.                                 |
| `front`       | `caddy:2-alpine`         | Copie le bundle, sert le front et relaie `/api/*` vers `back:8080`. | Image front finale                              |
| `back`        | `eclipse-temurin:17-jre` | Copie le JAR et l'exécute sur le port `8080`.                       | Image back finale                               |

- **Images optimisées** : le multi-stage build copie dans les images finales le bundle front ou le JAR, les images sont ainsi légères et leur surface d’attaque est réduite.
- **Build accéléré** : les manifests npm sont copiés avant le code source. S'ils restent identiques, Docker réutilise la couche `npm ci` et son cache.
- **Contexte réduit** : `.dockerignore` exclut les dépendances locales, les caches, les résultats de build et les fichiers Git afin d’alléger le contexte transmis à Docker.
- **Reproductibilité** : les versions Node, Caddy, Gradle et Java sont centralisées dans des arguments Docker et alignées avec la CI.
- **Exécution limitée** : le back-end utilise un utilisateur non-root ce qui limite les conséquences d'une compromission.
- **Routage applicatif** : Caddy sert les fichiers statiques du front-end et relaie les requêtes `/api/*` vers `back:8080` sur le réseau Docker.

Les cibles peuvent être vérifiées séparément :

- `docker build --target front -t microcrm-front:local .`
- `docker build --target back -t microcrm-back:local .`

### 3.2 `docker-compose.yml`

Le fichier [`docker-compose.yml`](../docker-compose.yml) orchestre les deux cibles du Dockerfile nécessaires au fonctionnement complet de MicroCRM.

| Service | Configuration                                                     | Vérification                                   |
| ------- | ----------------------------------------------------------------- | ---------------------------------------------- |
| `back`  | Construit la cible `back` et publie sur le port `8080`.           | Healthcheck HTTP sur `http://localhost:8080/`. |
| `front` | Construit la cible `front` et publie sur les ports `80` et `443`. | Healthcheck HTTP sur `http://localhost/`.      |

Le service `front` démarre après le healthcheck de `back`. Les volumes `caddy_data` et `caddy_config` conservent les données et la configuration de Caddy. Avec `CADDY_SITE_ADDRESS=:80`, l'environnement local utilise HTTP ; le port `443` est réservé à une configuration HTTPS adaptée.

#### Lancer l'application localement

Depuis la racine du dépôt, avec Docker Desktop et le plugin Docker Compose installés :

```shell
docker compose up -d --build
docker compose ps
```

Après le passage des healthchecks à l'état `healthy`, le front-end est accessible sur `http://localhost/` et l'API sur `http://localhost:8080/`. Pour arrêter l'environnement local sans supprimer les volumes Caddy :

```shell
docker compose down
```

La commande `docker compose config -q`, exécutée dans le pipeline, valide la syntaxe et la résolution des variables Compose. Le démarrage effectif ci-dessus vérifie la conteneurisation demandée par la mission.

#### Déploiement de l'application

Dans le périmètre de cette mission, le déploiement continu consiste à publier les images Docker validées dans GitHub Container Registry (GHCR). Après la réussite des tests, du build et du Quality Gate SonarQube, le job `docker` est exécuté lors d'un push sur `main`.

Il publie les images `microcrm-front` et `microcrm-back` avec un tag `latest` et un tag SHA. Le tag SHA identifie le commit construit de façon immuable ; il assure la traçabilité de la version mise à disposition. Le détail des actions GitHub associées est présenté dans la section 2.

## 4. Plan de testing périodique

La chaîne CI/CD vérifie automatiquement que l'application peut être testée, compilée et analysée avant la publication de ses images Docker.

### 4.1 Types de tests automatisés

Le plan couvre les tests automatisés existants, les contrôles de construction et l'analyse statique SonarQube. Il ne couvre pas les tests fonctionnels de bout en bout, les tests de charge ni les audits de dépendances ; ces contrôles constituent des améliorations ultérieures.

| Type                        | Objectif                                                                                                     | Exécution                                          | Critère de réussite                                                         |
| --------------------------- | ------------------------------------------------------------------------------------------------------------ | -------------------------------------------------- | --------------------------------------------------------------------------- |
| Tests front Jasmine/Karma   | Vérifier les composants et services Angular couverts.                                                        | `npm run test:coverage` via `run-tests.sh`         | Tous les tests passent ; les rapports JUnit et LCOV sont générés.           |
| Tests back JUnit            | Vérifier le contexte Spring Boot et l'accès aux données des repositories.                                    | `./gradlew clean test` via `run-tests.sh`          | Tous les tests passent ; les rapports JUnit et JaCoCo sont générés.         |
| Qualité et sécurité du code | Détecter les bugs, vulnérabilités potentielles, duplications et problèmes de couverture sur le nouveau code. | Scan SonarQube avec les rapports LCOV et JaCoCo.   | Le scan se complète et le Quality Gate passe avec 80% de coverage.          |
| Build applicatif\*          | Vérifier que les applications Angular et Spring Boot peuvent être compilées et packagées.                    | `npm run build` et `./gradlew build`               | Le bundle Angular et le JAR Spring Boot sont produits.                      |
| Configuration Compose\*     | Vérifier la syntaxe et les variables de `docker-compose.yml`.                                                | `docker compose config -q`                         | La configuration est valide.                                                |
| Images Docker\*             | Construire et publier les images exécutables validées.                                                       | `docker/build-push-action`                         | Les images sont publiées dans GHCR avec les tags `latest` et SHA du commit. |
| Contrôle des dépendances\*  | Détecter les vulnérabilités connues dans les dépendances front, back et les images Docker.                   | _Axe d’amélioration non implémentée actuellement._ | Aucune vulnérabilité critique et un rapport d'audit généré.                 |

\* Contrôles complémentaires de la CI : ils confirment que les applications et leurs conteneurs peuvent être produits après les tests.

### 4.2 Fréquence d'exécution

| Événement                    | Contrôles exécutés                                                                                                                         |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| **Pull request** vers `main` | Tests front et back, build, validation Compose, SonarQube et Quality Gate.                                                                 |
| **Push** vers `main`         | Tests front et back, build, validation Compose, SonarQube et Quality Gate + puis publication des images Docker dans GHCR.                  |
| **Autres branches**          | Aucun workflow CI, tant que les déclencheurs ne sont pas étendus.                                                                          |
| **Tag** `vX.Y.Z`             | Validation du tag, build du ZIP Angular et du JAR, et création d'une GitHub Release.                                                       |
| Exécution planifiée          | _Non implémentée_ : axe d’amélioration à mettre en place pour détecter les vulnérabilités des dépendances et alimenter les métriques DORA. |

### 4.3 Objectifs des tests

- **Qualité du code** : les builds et l'analyse SonarQube détectent les défauts techniques avant la publication des images.
  - Les builds signalent les erreurs de compilation ou de packaging du front-end et du back-end.
  - SonarQube analyse les bugs, vulnérabilités potentielles, duplications et problèmes de maintenabilité ; son Quality Gate est bloquant.

- **Non-régression** : les tests Angular et Spring Boot vérifient que les comportements déjà couverts restent stables après une modification.
  - Les composants, services et repositories sont testés automatiquement à chaque pull request et push vers `main`.
  - Les rapports JUnit centralisés dans GitHub Actions permettent d'identifier le test en échec et le commit concerné.

- **Fiabilité de livraison** : les contrôles confirment qu'une version peut être construite de manière reproductible avant sa publication dans GHCR.
  - Les artefacts Angular et Spring Boot sont construits, puis la configuration Docker Compose est validée.
  - Les mêmes commandes de tests, de build et de validation Compose sont disponibles localement et dans le runner Ubuntu de GitHub Actions.
  - Les images Docker ne sont publiées qu'après la réussite des tests, du build et du Quality Gate.

## 5. Plan de sécurité

Dans le workflow CI, le job sonar s’exécute après les tests et le build. SonarQube Cloud analyse le front Angular et le back Spring Boot à partir de `sonar-project.properties`, qui définit les sources, les binaires Java et les rapports de couverture LCOV et JaCoCo.
Le scan utilise le secret `SONAR_TOKEN`, puis vérifie le Quality Gate. Le job de publication des images Docker dépend de ce contrôle, son échec empêche la publication dans GHCR lors d’un push sur main.

### 5.1 Résultats SonarQube

L'analyse [SonarQube Cloud](screenshots/sonarqube-overview.png) distingue quatre catégories d'anomalies sur le code et les fichiers d'infrastructure classées par sévérité elle ne remplace ni une revue de code, ni un test d’intrusion, ni un audit de dépendances :

- une **vulnérabilité / security issue** : code potentiellement exploitable ;
- un **bug / reliability issue** : comportement erroné ou échec possible impactant la fiabilité ;
- un **code smell / maintainability issue** : dette technique de maintenabilité ;
- un **security hotspot** : code sensible demandant une revue humaine.

| Indicateur        | Résultat              | Analyse                                                                                             |
| ----------------- | --------------------- | --------------------------------------------------------------------------------------------------- |
| Quality Gate      | **Passed**            | La publication est autorisée, sans effacer la dette historique.                                     |
| Issues ouvertes   | **55**                | Liste de dette technique à réduire progressivement.                                                 |
| Security          | **4** (Rating **C**)  | 3 Medium et 1 Low : risque de code potentiellement exploitable.                                     |
| Security hotspots | **0** (Rating **A**)  | Aucun hotspot en attente de revue sur cette analyse.                                                |
| Reliability       | **32** (Rating **C**) | 1 High, 30 Medium et 1 Low : risque de comportement défaillant.                                     |
| Maintainability   | **21** (Rating **A**) | Dette à traiter progressivement ; la répartition par sévérité n’est pas reprise dans cette capture. |
| Duplication       | **2,5 %**             | Taux limité, mais à surveiller sur les futures évolutions.                                          |
| Couverture        | **37,4 %**            | Insuffisant pour sécuriser les régressions (viser 80 % de couverture)                               |

Le tableau suivant synthétise les principales alertes ouvertes regroupées par cause, à partir de la [liste des issues SonarQube](screenshots/sonarqube-issues.png) des fichiers et lignes concernés, afin de faciliter leur priorisation.

| Alerte                               | Statut                                                                                    | Risque                                                                                                                 |
| ------------------------------------ | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| **CORS permissif**                   | 3 issues Security/Medium dans la configuration REST                                       | OWASP A05 : `@CrossOrigin` sans restriction et `allowedOrigins("*")` ouvrent les endpoints à toute origine.            |
| **Erreur d’appel asynchrone**        | 1 issue marquée Reliability/High et Maintainability/High dans le constructeur             | L’initialisation peut échouer ou devenir difficile à tester.                                                           |
| **Promesses non résolues/capturées** | 12 issues Reliability Medium dans les composants Angular                                  | Les erreurs HTTP peuvent rester silencieuses et provoquer un chargement, une sauvegarde ou une navigation incohérents. |
| **Injection par champ**              | 2 issues marquées Reliability/Medium et Maintainability/Medium sur des annotations Spring | Le couplage est moins explicite, l’immutabilité est impossible et les tests sont plus complexes.                       |
| **Accessibilité de l’interface**     | 14 issues Reliability/Medium sur les formulaires et les en-têtes de tableau               | Formulaires moins accessibles et plus difficiles à maintenir ; structure de tableau ambiguë pour les lecteurs d’écran. |

### 5.2 Analyse des risques

| Risque                                          | Constat                                                                                                                                            | Mesure                                                                                                                             |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Contournement des validations avant publication | La publication sur `main` dépend du job Docker mais les règles de protection de cette branche ne sont pas versionnées.                             | Exiger une pull request, les contrôles de tests et du Quality Gate avant fusion, et interdire les pushes directs sur `main`.       |
| Critères du Quality Gate devenus inadaptés      | Le Quality Gate est administré dans SonarQube Cloud, ses critères peuvent ne plus correspondre à l’évolution du code ou aux exigences du projet.   | Revoir périodiquement les critères du Gate et les adapter : seuils d’issues, couverture, duplication et exigences de sécurité.     |
| Dépendances vulnérables non détectées           | Aucun audit NPM/Gradle, inventaire des dépendances ou verrouillage Gradle ne sont présents dans la CI.                                             | Ajouter les audits npm et Gradle, générer une SBOM et traiter les alertes dans des pull requests dédiées.                          |
| Publication d’une image vulnérable              | Les images du `Dockerfile` sont référencées par tags puis construites et publiées dans GHCR sans scan de vulnérabilités.                           | Scanner les images avant publication, échouer selon des seuils définis et pinner les images de base par digest.                    |
| Màj non maîtrisés des actions et images tierces | Les actions GitHub sont référencées par tags majeurs et les images de base par tags de version.                                                    | Pinner les actions GitHub sur des SHA vérifiés et gérer leurs mises à jour dans des pull requests contrôlées.                      |
| Compromission d’un secret CI                    | `SONAR_TOKEN` est fourni par les secrets GitHub et le `GITHUB_TOKEN` est limité au job Docker, mais les droits d’accès sont configurés hors dépôt. | Appliquer le moindre privilège, limiter l’accès aux secrets, les modifier périodiquement et surveiller les journaux des workflows. |

### 5.3 Plan d’action / remédiation

| Échéance    | Action vérifiable                                                                                       | Résultat attendu                                                                |
| ----------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Immédiat    | Corriger ou justifier toute issue SonarQube Blocker ou High avant publication.                          | Aucune issue Blocker ou High non justifiée n’est publiée.                       |
| Immédiat    | Déplacer les appels asynchrones hors des constructeurs et gérer les erreurs HTTP.                       | L’issue High est corrigée et les erreurs sont traitées.                         |
| Court terme | Ajouter des tests sur les parcours métier, les erreurs et les opérations CRUD.                          | La couverture dépasse 37,4 % et les régressions sont mieux détectées.           |
| Court terme | Corriger les issues Medium de sécurité (OWASP A05), fiabilité et accessibilité.                         | Réduction des risques et des issues.                                            |
| Court terme | Réduire la duplication après ajout de tests.                                                            | La duplication baisse sans régression.                                          |
| Court terme | Activer la protection de `main` : Imposer les pull requests, les tests et le Quality Gate avant fusion. | Aucun changement non validé sur `main`.                                         |
| Long terme  | Ajouter un audit des dépendances et un inventaire des dépendances à la CI.                              | Les vulnérabilités de dépendances sont détectées avant publication (OWASP A06). |
| Long terme  | Scanner les images avant publication avec des versions fixes d’images et d’actions CI.                  | Les images et composants tiers sont mieux maîtrisés (OWASP A08).                |
| Long terme  | Adapter le Quality Gate aux exigences du projet et traiter les issues Low.                              | Les nouvelles régressions sont bloquées et la dette diminue.                    |
| Long terme  | Réviser régulièrement les droits, la rotation et l’usage des secrets CI.                                | Les secrets conservent un périmètre limité.                                     |

## 6. Monitoring, métriques & KPI

La mise en place locale d’ELK repose sur le fichier docker-compose-with-elk.yml :

- Elasticsearch est exposé sur le port `9200`, Logstash reçoit les journaux JSON sur le port `5044` et Kibana rend leur consultation disponible sur le port `5601`,
- Le profil Spring `elk` configure Logback et transmet les logs JSON du back à Logstash. Caddy envoie ses logs HTTP au format JSON du front à Logstash,
- Logstash enrichit les logs puis les indexe dans `microcrm-logs-*` afin de corréler les événements applicatifs et les requêtes HTTP.
- `docker compose -f docker-compose-with-elk.yml up -d --build` lance le monitoring et le data view `microcrm-logs-*` est créé dans Kibana.

### 6.1 Métriques DORA

| Métrique                    | Méthode de calcul                                                                                                              | Source des données               | Résultat                                                                                                     |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | -------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Lead Time for Changes       | Écart entre le premier commit d’une branche et sa publication après merge sur main.                                            | GitHub Actions                   | 79 h (ed4dc6f → 13c8818); 7 h (c6cd51e → 6f7c9ee); 15 h (ac1bab6 → b848510); Valeur retenue : 15 h (médiane) |
| Deployment Frequency        | Nombre de mises en production réussies ÷ jours observés.                                                                       | GitHub Actions                   | Run #9 le 28/09; Run #13 le 29/09; Run #15 le 30/09; Valeur retenue : 1 publication/jour                     |
| Mean Time to Restore (MTTR) | Durée entre la détection d'un pic d'erreurs (microcrm-logs-\* → level.keyword: "ERROR") et le timestamp de retour à la normale | ELK / Kibana                     | Aucune erreur détectée sur les trois exécutions. Valeur retenue : non calculable                             |
| Change Failure Rate         | (Déploiements ayant causé un incident ÷ total des déploiements observés) × 100                                                 | GitHub Actions + corrélation ELK | Run #9 : aucune erreur; Run #13 : aucune erreur; Run #15 : aucune erreur; Valeur retenue : 0 %               |

### 6.2 KPI personnalisés

| KPI                         | Méthode de calcul                                                             | Source         | Valeur observée             | Seuil cible        |
| --------------------------- | ----------------------------------------------------------------------------- | -------------- | --------------------------- | ------------------ |
| Temps de build front        | Somme des steps "Install Front-End dependencies" + "Build Front-End"          | GitHub Actions | 14s (moyenne sur 3 runs)    | Stabiliser (- 20s) |
| Temps de build back         | Durée du step "Build Back-End (Gradle)"                                       | GitHub Actions | 19s (moyenne sur 3 runs)    | Stabiliser (- 30s) |
| Temps d'exécution des tests | Durée du job "tests" (exécution unifiée front/back et rapports de couverture) | GitHub Actions | 1m 39s (moyenne sur 3 runs) | Stabiliser (- 2m)  |
| Couverture de tests         | % lignes couvertes, Jacoco (back) + rapport LCOV (front)                      | SonarQube      | 37.4%                       | Améliorer (~ 80%)  |
| Taux de logs ERROR          | (nombre de logs ERROR ÷ nombre total de logs) × 100                           | ELK / Kibana   | 0% (cf. § 6.1)              | Stabiliser (0%)    |

### 6.3 Analyse synthétique du monitoring

#### Tendances observées

- Le Lead Time varie avec la taille des changements : la PR ELK (commit unique) est plus rapide que la PR de configuration CI/CD (plusieurs jours). L'échantillon de 3 publications est trop réduit pour conclure à une amélioration, y compris pour le MTTR et le Change Failure Rate.
- Le rythme de publication est régulier, sans rollback ni correctif d'urgence.
- Les temps de build sont stables. Seul le run #13 est plus lent (front et back), ce qui suggère une cause externe (cache, charge du runner).

#### Points forts

- Le pipeline est fiable : 100% de succès CI, les durées de builds et de tests sont sous les seuils cibles définis et sans incident.
- L'observabilité est opérationnelle : les logs back (Logback) et HTTP (Caddy) sont centralisés dans microcrm-logs-\*. Une erreur simulée est bien remontée dans Kibana, donc l'absence d'erreur reflète la réalité.

#### Points à améliorer

- La couverture (37,4%) est le point critique avec la dette technique de 55 issues Sonar dont 32 de fiabilité. Les issues Angular (promesses non gérées, erreurs HTTP silencieuses) risquent de provoquer des incidents non détectés.
- Un Change Failure Rate de 0% est peu significatif tant que la majorité du code n'est pas testée : la dette reste latente, sans réelle erreur observée dans Kibana.
- Le MTTR n'est pas calculable : à réévaluer sur un historique plus long.
- Le job de tests unifié ne permet pas d'isoler la durée front et back.

#### Dashboards

- Les 6 visualisations Kibana (cf. Annexe 6) couvrent l'activité, la santé (niveaux et fréquence d'erreurs) et la performance (latence moyenne côté Caddy) permettant de corréler un pic de logs à une mise en production.
- La vue Discover (cf. Annexe 7) donne le détail des événements

#### Alertes

- Côté exploitation, une notification dès que le taux de logs ERROR dépasse un seuil permettrait de détecter un incident et de mesurer le MTTR.
- Côté qualité, le Quality Gate bloque déjà la dégradation du nouveau code.

## 7. Plan de sauvegarde des données

### 7.1 Ce qui doit être sauvegardé

| Élément                   | Commentaire                                                                                                                                                                                                               |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Données applicatives      | _Limitation_ : l'architecture repose sur une base HSQLDB embarquée non persistée. Si une base de données persistante est ajoutée, il faudra prévoir des sauvegardes automatisées et une procédure de restauration testée. |
| Fichiers de configuration | Les fichiers Docker Compose, Dockerfile, workflows GitHub Actions, configuration Caddy (nécessaire en HTTPS) et Logstash sont versionnés dans Git.                                                                        |
| Images Docker             | Les images OCI `microcrm-front` et `microcrm-back` sont publiées dans GitHub Packages / GitHub Container Registry pour exécuter l’application conteneurisée.                                                              |
| Artefacts de release      | JAR Spring et ZIP Angular archivés avec tag `vX.Y.Z` dans GitHub Release.                                                                                                                                                 |
| Secrets                   | Stockés dans GitHub Actions ou un fichier d’environnement non versionné.                                                                                                                                                  |
| Volumes Caddy             | _Limitation_ : à sauvegarder uniquement si HTTPS est activé avec un nom de domaine pour persister les certificats et données Caddy. (Inutile en HTTP)                                                                     |

### 7.2 Procédure de sauvegarde

| Élément               | Format                                                         | Fréquence                               | Outils / méthode                                                                                       |
| --------------------- | -------------------------------------------------------------- | --------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Code et configuration | Versionnés dans dépôt le Git avec tags de version              | Chaque push                             | `git push` : historique et tags sont conservés dans le dépôt distant.                                  |
| Images Docker         | `microcrm-front` et `microcrm-back` tagués avec SHA du commit. | Chaque pipeline CI/CD validé sur `main` | Workflow CI/CD reconstruit et publie automatiquement les images dans GHCR après validation sur `main`. |
| Artefacts de release  | Archive Angular .zip et JAR Spring Boot .jar                   | Chaque tag valide `vX.Y.Z`              | `release.yml` reconstruit et ajoute les archives à GitHub Release au push du tag                       |
| Secrets               | Secrets GitHub Actions                                         | Ajout ou édition                        | GitHub liste les noms de clés conservée sans valeur.                                                   |

### 7.3 Procédure de restauration

| Scénario                                    | Risque                                                                       | Action de restauration                                                                                                                                                 |
| ------------------------------------------- | ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Version défectueuse publiée sur `main`      | Pic de logs `ERROR` dans Kibana (`microcrm-logs-*`), healthcheck `unhealthy` | Grâce au build reproductible et aux images taguées par SHA de la CI, la restauration est simplifiée : retour au commit stable, contrôle des logs et correction via PR. |
| Version publiée sur `main` sans release tag | Aucun artefact JAR/ZIP archivé, version non traçable avec SHA                | Poser le tag sur le commit validé pour déclencher `release.yml`                                                                                                        |
| Release `vX.Y.Z` défectueuse                | Bug constaté, artefacts JAR ou ZIP inutilisable au démarrage                 | Réutiliser la release précédente, puis publier un correctif en `vX.Y.(Z+1)`                                                                                            |
| Pipeline en échec avant publication         | Job `tests`, `build`, `sonar` ou `docker` en échec                           | Corriger sur la branche ou annuler la PR ; `main` n'est pas impacté grâce au Quality Gate.                                                                             |
| Secret compromis ou expiré                  | Échec du scan Sonar ou refus de publication GHCR.                            | Révoquer puis générer le token, mettre à jour dans GitHub Secrets, relancer workflow                                                                                   |

## 8. Plan de mise à jour

### 8.1 Mise à jour de l’application

#### Processus de mise à jour

Toute évolution fonctionnelle, corrective ou technique est réalisée dans une branche dédiée, puis :

- proposée par une pull request vers `main`,
- intégrée après la réussite des tests, du build et du Quality Gate SonarQube,
- mergée sur `main` déclenchant la publication des images Docker,
- tagué `vX.Y.Z` lorsqu'une version doit être publiée.

#### Dépendances Gradle et npm

- Le front utilise `package.json` et `package-lock.json` pour gérer les dépendances npm. Lorsqu’une dépendance est mise à jour, ces fichiers sont versionnés avec la modification. La CI installe ensuite les versions verrouillées avec `npm ci`.
- Le back utilise Gradle Wrapper 8.7. Les plugins et dépendances sont définis dans `back/build.gradle` et toute mise à jour est validée par les tests et le build.
- Les mises à jour des frameworks (Angular, Spring) et langages (Java, TS) sont réalisées avec les guides de migration officiels et validées par les tests et le build.
- Les dépendances critiques ou présentant un correctif de sécurité sont traitées en priorité. Les dépendances inutilisées sont supprimées plutôt que conservées.

#### Images Docker

- Les images de base de l’application sont définies dans les arguments du Dockerfile : Node.js 20, Gradle 8.7/JDK 17, Caddy 2 et Eclipse Temurin 17.
- La mise à jour de ces versions est à réaliser dans une pull request dédiée. La CI vérifie alors la configuration Compose avec : `docker compose config -q`.
- Après le merge sur main, la CI reconstruit les cibles `front` et `back` et les publie dans le GitHub Container Registry avec les tags latest et le SHA du commit.
- Le démarrage des conteneurs doit être vérifié avec : `docker compose up --build` ; puis par le contrôle de l’accès au front-end et à l’API.
- En cas de régression sur un environnement utilisant les images GHCR, le retour en arrière consiste à sélectionner le tag SHA du dernier commit validé.

### 8.2 Mise à jour du pipeline CI/CD

#### Versions des actions GitHub

- Les actions GitHub doivent être mises à jour dans une pull request dédiée, après consultation de leur documentation officielle et de leurs notes de version.
- Les actions utilisées sont actuellement épinglées par version majeure (`@v7`, `@v6`). Pour renforcer la sécurité, elles pourront être épinglées par SHA de commit.
- Après chaque mise à jour, la CI doit réussir sur une pull request avant sa fusion.

#### Scripts et configuration du workflow

- Les versions Node 20 et Java 17 définies dans la CI doivent rester alignées avec l’application et le `Dockerfile`.
- Les scripts de test, les chemins des rapports de couverture et les configurations Docker Compose sont à contrôler à chaque changement de structure du projet.
- Les runners `ubuntu-latest` peuvent subir des breaking changes et doivent donc être surveillés régulièrement.

#### Maintenance du workflow

- La pipeline doit être revue après une évolution majeure d’Angular, Spring Boot, Java, Gradle ou Docker (mise à jour des images et des actions).
- Une modification du pipeline ne doit pas supprimer les étapes de tests, de build, d’analyse SonarQube ou de publication des images sans justification.
  Les KPI, leurs seuils, les contrôles de qualité et les procédures de sauvegarde et de restauration (section 7) doivent être réévalués lors des évolutions majeures.

### 8.3 Fréquence & bonnes pratiques

#### Fréquence

- Une revue des dépendances, des images de base, des actions GitHub et des procédures de sauvegarde et de restauration doit être effectuée mensuellement.
- Un correctif de sécurité critique doit être traité dès sa publication.
- Planifier les mises à jour majeures séparément afin d’anticiper les changements de compatibilité.

#### Bonnes pratiques

- Consulter les notes de version et les guides de migration avant toute évolution majeure.
- Limiter chaque mise à jour à un périmètre réduit pour faciliter l’identification d’une régression.
- Valider toute modification par les contrôles CI : tests, build, analyse SonarQube et validation de la configuration Docker Compose.
- Conserver les fichiers de dépendances et de configuration versionnés en s'appuyant sur les gestionnaire de paquets officiel.
- Créer un tag de release uniquement après la réussite de la CI afin d’assurer la traçabilité du livrable.
- Automatiser à terme la détection des mises à jour des dépendances, des images Docker et des actions GitHub.

## 9. Conclusion

Les principales améliorations apportées par l’industrialisation du pipeline CI/CD de MicroCRM sont les suivantes :

- Les opérations manuelles sont remplacées par une chaîne de livraison reproductible : les tests Angular et Spring Boot, le build, l’analyse SonarQube et la validation de Docker Compose sont exécutés avant la publication.
- Les images front-end et back-end sont construites puis publiées dans GHCR après validation sur `main`, tandis que les tags `vX.Y.Z` produisent des releases traçables contenant les artefacts Angular et Spring Boot.
- La documentation, les rapports de test, les métriques et la centralisation locale des logs complètent ce dispositif en facilitant l’exploitation et le diagnostic.

Bien que les indicateurs portent sur un échantillon limité pour conclure à une tendance fiable, les premiers résultats confirment les bénéfices attendus :

- Les trois publications observées ont réussi sans incident détecté, soit un taux de succès CI de 100 % et un Change Failure Rate mesuré à 0 %.
- Les builds front-end et back-end durent respectivement 14 s et 19 s en moyenne, et le job de tests 1 min 39 s ; ces durées sont sous les seuils fixés.
- Les caches, les contrôles exécutés à chaque pull request et les livrables versionnés réduisent le temps et le risque associés à une mise à disposition.

La qualité reste le principal axe de progression même si le Quality Gate SonarQube et les tests existants détectent déjà les régressions avant la publication de nouveau code. Les itérations suivantes devront, par ordre de priorité :

1. Augmenter la couverture des parcours métier, des cas d’erreur et des opérations CRUD, pour respecter le seuil de couverture du Quality Gate.
2. Corriger ou justifier les issues SonarQube critiques et High, puis traiter les issues Medium de sécurité, de fiabilité et d’accessibilité.
3. Protéger `main` en imposant les pull requests avec les contrôles CI et le Quality Gate avant toute fusion ; séparer également les durées de tests front-end et back-end pour mieux détecter une dérive.
4. Ajouter un audit des dépendances et un scan des images Docker avant publication ; épingler à terme les actions et images de base par SHA ou digest.
5. Préparer l’évolution vers une base de données persistante avec volume dédié, sauvegardes automatisées et tests réguliers de restauration.
6. Consolider les métriques DORA et les alertes ELK sur davantage de publications et ajouter une exécution planifiée des tests et des contrôles de sécurité afin d’ajuster les seuils, de mesurer le MTTR et de piloter l’amélioration continue.

Cette base CI/CD répond ainsi aux besoins de fiabilité, de rapidité et de qualité exprimés pour MicroCRM, tout en donnant une trajectoire claire pour renforcer la sécurité, la couverture de tests et la maturité opérationnelle.
