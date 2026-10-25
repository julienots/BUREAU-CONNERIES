# OFFICE MAYHEM — SuperEssence Studio

Jeu 3D d'infiltration et de comédie physique au bureau. Fais des bêtises sans te faire prendre par le directeur.
Moteur : **Godot 4.5.1** (GDScript typé, physique Jolt). Plan technique : [`docs/PLAN.md`](docs/PLAN.md).

## Lancer le jeu

| Plateforme | Comment |
|---|---|
| Android | Installer `OfficeMayhem.apk` (Android 7+, arm64 ou armv7). Autoriser « sources inconnues ». |
| PC (Windows) | `OfficeMayhem.exe` |
| PC (Linux) | `./OfficeMayhem.x86_64` |
| Depuis les sources | `godot --path .` (Godot 4.5.1) |

Les binaires se reconstruisent avec les commandes de la section « Construire ».

## Commandes

**Téléphone (paysage)** — pouce gauche : joystick qui apparaît sous le doigt (pousser jusqu'au bord = courir) ·
pouce droit : glisser pour tourner la caméra (elle suit aussi automatiquement) · gros bouton **jaune** = l'action
affichée dessus (« Prendre », « S'asseoir »…), ◀ ▶ pour changer d'action, ou toucher directement une ligne de la liste ·
Lâcher / Lancer / Se lever apparaissent seulement quand c'est utile · Accroupi (bascule) · en haut : bandeau
**Mission** (touche-le pour la liste), **II** = pause, **BOUTIQUE** (jaune). Plusieurs doigts en même temps fonctionnent
(joystick + bouton), et un objet traîné loin se reprend (« Traîner », « Redresser la chaise » si elle est renversée).

**PC** — ZQSD/WASD (touches physiques, AZERTY ok) · souris = caméra · E ou clic = agir · F = action secondaire ·
Tab / molette = action suivante · Maj = courir · Ctrl = s'accroupir · G = lâcher · clic droit = lancer ·
1-4 = objets · R = déclencher le buzzer · O = objectifs · B = boutique · Échap = pause. Tout est reconfigurable (Paramètres).
Manette : stick gauche/droit, A agir, X secondaire, B lâcher.

## Ce qui est implémenté (et vérifié)

| Système | État | Vérification |
|---|---|---|
| Bureau 3D procédural (9 zones, 25 postes, portes, vitres, fenêtres, lumières, ~200 objets interactifs) | ✅ | captures d'écran rendues |
| Physique Jolt : chaises roulantes, piles de cartons qui s'écroulent, papiers glissants, tasses qui cassent, sons selon matériau et force | ✅ | test e2e (tour stable au repos, s'effondre si on la pousse, bruit « crash ») |
| Personnages 3D animés (procédural : marche calée sur la distance, assis, frappe, porter, accroupi, regard, 15 émotions, trébucher, chute, relevé) | ✅ | rendus + simulation (personne ne traverse le sol) |
| 14 collègues autonomes (11 archétypes, besoins, emploi du temps, réunions, déjeuner, relations, rumeurs, dénonciations, mensonges, complices, petites infractions) | ✅ | simulation headless d'une journée |
| Directeur IA : vision (cône + raycasts + attention progressive), audition atténuée par les murs, mémoire bornée et alibis, enquêtes, interrogatoires de témoins, inspections, 5 profils, pièges (manipulateur) | ✅ | tests unitaires + e2e (pris sur le fait → interrogatoire → sanction) |
| Témoignages sincères / partiels / mensongers, contradictions, fausses accusations réfutées par alibi | ✅ | tests unitaires |
| 30 missions + 3 défis (règles réelles côté autorité) | ✅ | contrôle statique des 30 ; 5 réussies en e2e |
| Deux boutiques — **Farces & Attrapes** (10 farces : klaxon, poil à gratter, faux cafard, boule puante, serpent en boîte, pistolet à eau, coussin péteur…) et **SuperAmazone** (gadgets) — accessibles depuis le menu principal et en jeu (bouton BOUTIQUE) ; chaque farce réussie rapporte une **prime** | ✅ | `farce_test` (22 vérifs) |
| Jauge **« Le chef »** (confiance du directeur 0-100 : monte si tu travailles, flattes, offres un café, dénonces à raison ; baisse si tu es pris, absent en réunion, suspect…) qui change la vitesse des soupçons, les interrogatoires et le salaire | ✅ | unitaires + e2e |
| IA réactives : « ! » / « ? » au-dessus des collègues qui voient/entendent, râlent si on les bouscule, si on prend leurs affaires, si on s'assoit sur leur chaise, si on court ou lance des objets près d'eux ; téléphones qui sonnent, clavier qui crépite | ✅ | simulation + tests |
| Économie, salaire, amendes, stock (poches pleines → stock) | ✅ | e2e |
| Missions sur un **post-it** (panneau manuscrit + vrai post-it collé sur l'écran de ton PC, « Lire le post-it ») | ✅ | captures |
| **Réunions** : tout le monde y va ; le chef alterne « parle à la table » / « écrit au tableau » (dos tourné = le moment de faire le con) ; 6 bêtises (grimaces, ronfler, pet buccal, boulette de papier, toupie sur la chaise, imiter le chef) ; 6 missions de réunion risquées mais bien payées (80 à 160 €), une proposée chaque jour | ✅ | `meeting_test` (15 vérifs) |
| **14 collègues** (6 nouveaux : stagiaire, commère, flemmard…), 12 places en réunion | ✅ | tests |
| **Visite du PDG** (certains jours) : arrive par l'ascenseur, fait le tour escorté par le chef, s'assoit dans son fauteuil ; tout le monde fait semblant de bosser ; farce sur le PDG = +50 € mais gros risque ; 3 farces et il s'enfuit ; 3 missions bonus | ✅ | `pdg_test` (14 vérifs, tour complet) |
| Physique cartoon : salto sur peau de banane, envol quand on est percuté, étoiles autour de la tête, pousser une chaise **avec quelqu'un dessus** (éjecté s'il percute un mur), « se propulser en chaise », canard qui rebondit | ✅ | `physics_test` (12 vérifs) |
| Travail : 3 mini-tâches (mails, tampons, saisie), productivité, « faire semblant » détectable | ✅ | |
| 13 événements imprévus équilibrés | ✅ | tests unitaires |
| Sauvegarde locale versionnée (+ migration), paramètres, touches | ✅ | e2e |
| Écran de démarrage SuperEssence Studio, menu 3D, personnalisation, paramètres, crédits, tutoriel interactif | ✅ | captures |
| SFX de bureau (77) et **voix en charabia** (240 répliques, 10 voix × 8 émotions), musiques | ✅ | générés par `tools/gen_audio.py` |
| Multijoueur : **Internet sans serveur** (relais MQTT public, code de 4 lettres, liste des parties publiques), même Wi-Fi, serveur dédié / maître, salon, rôles, revanche | ✅ | `tools/relay_test.sh` (journée complète + revanche via un broker MQTT local), `tools/relay_ui_test.sh` (2 jeux passent par le vrai menu), `tools/mp_test.sh` |
| IA générative locale facultative (compatible Ollama) | ⚠️ partiel | code non bloquant ; pas testé avec un vrai modèle |

## Limites connues (honnêtement)

- **APK non testé sur un vrai téléphone** : il est signé (v2/v3) et le rendu « Mobile » a été vérifié sur PC,
  mais performances et confort tactile restent à valider sur appareil. Signé avec une clé de **debug**
  (pour le Play Store il faudra une clé de release).
- Les chutes utilisent une bascule physique contrôlée, pas un ragdoll complet.
- Multijoueur Internet testé avec un broker MQTT **local** (mêmes protocoles) : l'environnement de build ne peut
  pas joindre les relais publics, donc la connexion au relais public n'a pas pu être testée d'ici. Latence ≈ celle
  du relais (100–300 ms). La physique des objets est simulée par l'hôte, les autres interpolent. La reconnexion est implémentée mais n'a pas de test automatisé.
- Modèles 3D entièrement procéduraux (sites d'assets bloqués depuis l'environnement de build).
- Pas de version Web (ENet) ni iOS.

## Multijoueur — jouer en ligne

**Sur Internet, sans serveur à installer** : Jouer en ligne → « CRÉER UNE PARTIE » (le téléphone/PC qui crée
la partie l'héberge) → donner le code de 4 lettres aux amis → ils tapent le code dans « REJOINDRE AVEC LE
CODE » (ou choisissent la partie dans la liste des parties publiques). Le trafic passe par un relais MQTT
public et gratuit, chiffré (WebSocket TLS) : `broker.emqx.io`, puis `broker.hivemq.com`, puis
`test.mosquitto.org` si le premier ne répond pas (`src/net/relay_peer.gd`). Un autre relais peut être imposé
avec `--relay=wss://…` ou le paramètre `relay_url`.

**Même Wi-Fi / partage de connexion** : « Héberger ici », les autres tapent l'IP affichée chez l'hôte.

**Avancé — ton propre serveur** (VM avec ports UDP ouverts) :
```
godot --headless --path . -- --master --port=24680      # annuaire + codes, crée les salons (ports 24681+)
godot --headless --path . -- --server --port=24681       # ou un salon seul, sans annuaire
godot --headless --path . -- --server --relay=wss://broker.emqx.io:8084/mqtt --code=ABCD   # salon dédié via le relais
```
1 directeur humain + 1 à 8 employés ; si le directeur se déconnecte, l'IA prend le relais.

## Tests

```
tools/check.sh                                                   # compile tous les scripts
godot --headless --path . res://tests/run_tests.tscn             # 296 tests unitaires/statiques
godot --headless --path . res://tests/player_flow.tscn           # 26 vérifications de bout en bout
godot --headless --path . res://tests/farce_test.tscn            # les 6 nouvelles farces + primes
godot --headless --path . res://tests/touch_test.tscn            # vrais évènements tactiles multi-doigts
godot --headless --path . res://tests/meeting_test.tscn          # réunions, bêtises, missions de réunion
godot --headless --path . res://tests/pdg_test.tscn              # visite du PDG
godot --headless --path . res://tests/physics_test.tscn          # physique cartoon
godot --headless --path . res://tests/sim_day.tscn -- --secs=300 --scale=4   # journée simulée
tools/mp_test.sh 170                                             # serveur + 3 clients bots
tools/master_test.sh                                             # serveur maître
```

## Construire

```
python3 tools/gen_audio.py && python3 tools/gen_textures.py     # régénère sons/voix/textures (numpy, Pillow, espeak-ng, sox)
godot --headless --path . --export-debug "Android" build/OfficeMayhem.apk
godot --headless --path . --export-release "Windows Desktop" build/OfficeMayhem.exe
```
(Android : templates d'export Godot 4.5.1 + `apksigner`/`zipalign` configurés dans les paramètres de l'éditeur.)

## Structure

`src/autoload` (données validées, paramètres, sauvegarde, audio, réseau) · `src/world` (bureau, meubles, objets,
appareils, portes) · `src/characters` · `src/player` · `src/ai` (perception, mémoire, soupçons, témoignages,
cerveaux) · `src/gameplay` (session autoritaire, missions, économie, événements, journée) · `src/ui` · `src/net` ·
`data/*.json` (personnages, objets, missions, événements, dialogues) · `tests/` · `tools/`.

Polices Lilita One, Fredoka & Patrick Hand : SIL Open Font License ; Permanent Marker : Apache 2.0 (`assets/fonts`, via Fontsource).
