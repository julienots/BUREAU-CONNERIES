# OFFICE MAYHEM — Plan technique (Étape 1)

Studio : **SuperEssence Studio** (logo affiché au démarrage).

## 1. Analyse de l'existant

Le dépôt était vide (aucun commit, aucune ressource). Rien n'a donc été supprimé ni remplacé.

## 2. Choix du moteur : Godot 4.5 (et pas Unity)

| Critère | Godot 4.5 | Unity 6 |
|---|---|---|
| Export APK | Template officiel, export en ligne de commande, testé ici | Nécessite l'éditeur + licence activée, impossible en conteneur sans GUI |
| Licence | MIT, aucune redevance | Propriétaire, conditions changeantes |
| Physique | **Jolt** intégré (stable sur les piles d'objets) | PhysX (très bon) |
| Réseau | ENet + API multijoueur haut niveau + serveur dédié headless | Netcode for GameObjects (bon, plus lourd) |
| Poids APK | ~30–60 Mo | ~80–150 Mo |
| Tests auto | `godot --headless` exécute nos tests et des bots réseau | Possible, plus lourd |

**Conclusion : Godot 4.5** est le meilleur choix pour ce projet : il permet de construire, tester et exporter
l'APK entièrement par ligne de commande, et le même binaire sert de serveur dédié headless.
Langage : **GDScript typé** (pas de C#, pour garder un export Android simple et léger).

Conséquences :
- **Rendu** : Forward+ sur PC (SSAO, glow, ombres douces), renderer *Mobile* sur Android (préréglages qualité).
- **Physique** : Jolt, 60 Hz, mise en veille automatique des corps immobiles, budget de corps actifs.
- **IA** : 100 % locale (machines à états + utilité + perception + mémoire), aucune API payante.
  Un LLM local (Ollama, etc.) est un *plugin optionnel* via HTTP, désactivé par défaut, jamais bloquant.
- **Réseau** : ENet (UDP). Le serveur fait autorité. Vercel n'est **pas** adapté : le serveur doit tourner
  sur une VM/conteneur avec port UDP ouvert (`godot --headless -- --server`).

## 3. Direction artistique

Style « jouet de bureau » stylisé, cohérent, lisible : modèles 3D procéduraux (boîtes arrondies, profilés,
cylindres, tores), textures générées (bois, moquette, carrelage, carton, affiches, fonds d'écran) avec
normal maps, éclairage travaillé (soleil par les fenêtres, dalles lumineuses, SSAO, tonemapping AgX).
Les sites d'assets CC0 (Kenney, Quaternius, Poly Pizza) sont bloqués depuis l'environnement de build :
tout est donc **généré par code**, ce qui garantit l'absence de dépendance externe.

Personnages : humanoïdes stylisés articulés (≈17 articulations), animation **procédurale** (marche
calée sur la distance parcourue = pas de glisse, assis, frappe clavier, port d'objet, regard, émotions,
trébuchement, chute, relevé). Chutes : bascule physique contrôlée + relevé (pas de ragdoll permanent).

## 4. Architecture des fichiers

```
project.godot / export_presets.cfg
assets/   fonts, branding (logo SuperEssence), textures, audio/sfx, audio/voices (charabia), audio/music
data/     items.json, missions.json, characters.json, events.json, dialogue.json   (validés au chargement)
src/
  autoload/  data.gd (registre validé), settings.gd, save.gd, audio.gd, events.gd (bus), net.gd, game.gd
  core/      ids, mesh_kit (modélisation procédurale), materials, layers
  world/     office_builder (plan, pièces, portes, fenêtres), furniture, props (objets physiques),
             door, zone (acoustique), light_switch, devices (imprimante, café, micro-ondes, radio, téléphone)
  characters/ humanoid (rig), animator (procédural), character (CharacterBody3D, collisions, chutes)
  player/    controller, camera, interactor, inventory
  ai/        sound_system, perception, memory, coworker_brain, director_brain, testimony, relations
  gameplay/  session (autorité), actions, missions, mission_rules, economy/shop, work_tasks,
             event_director, day_manager, denunciation/interrogation, tutorial
  dialogue/  barks (modèles de phrases), voice (charabia), llm_provider (optionnel)
  ui/        theme, splash, main_menu, hud, mobile_controls, shop, work, talk, interrogation,
             results, settings, customization, lobby, credits
  net/       protocol, lobby, replication, bots de test
tests/      run_tests.gd + tests unitaires et d'intégration headless
tools/      gen_audio.py, gen_textures.py, build_apk.sh, run_server.sh, mp_test.sh
```

Règle clé : **une seule source de vérité**. Toute action passe par `Session.request_action()`.
En solo la session tourne localement (pair hors-ligne = autorité). En ligne, le client envoie une
*intention*, le serveur valide (distance, prérequis, cadence) puis applique. L'UI n'affiche que l'état.

## 5. Systèmes de gameplay

- **Son → perception** : chaque bruit = `SoundEvent{position, intensité, type}` ; atténuation par
  distance + murs/portes (raycasts sur la couche acoustique). Entendre ≠ identifier l'auteur.
- **Vision** : cône + portée + raycasts multi-points (tête/torse) + accumulation progressive de
  l'attention ; vitres transparentes, murs/meubles opaques ; accroupi derrière un meuble = caché.
- **Actes** : toute bêtise produit un `Act` (auteur, gravité, position, objet). Les témoins qui le voient
  le mémorisent avec une confiance ; le directeur ne connaît que ce qu'il a perçu ou ce qu'on lui dit.
- **Soupçons** : score par employé → 6 niveaux (Aucun → Infraction confirmée), décroissance lente.
- **Mémoire** limitée et réglable (observations, alibis, zones à problèmes, fiabilité des témoins).
- **Témoignages** : sincères / partiels / mensongers ; contradictions et alibis réfutent les fausses
  accusations (qui se retournent contre leur auteur).
- **Collègues** : besoins (travail, café, social, toilettes) + emploi du temps + 8 archétypes +
  relations ; ils commettent aussi de petites infractions, bavardent, propagent des rumeurs, dénoncent.
- **Directeur** : 5 profils (paranoïaque, autoritaire, manipulateur, distrait, méthodique) qui changent
  ses seuils et priorités (patrouille, enquête, interrogatoire, inspection, piège).
- **Missions** : données JSON + règles codées par type de condition ; 30 missions visées.
- **Économie/boutique** : argent fictif, gadgets avec effets, prix, limites et risques.
- **Productivité** : mini-tâches courtes (mails, tampons, saisie) ; feindre de travailler a des limites.
- **Événements** : inspection, réunion avancée, imprimante bloquée, appel du directeur, visiteur, etc.
- **Audio** : SFX de bureau générés + **voix rigolotes en charabia** (synthèse espeak-ng retravaillée).

## 6. Multijoueur

Serveur dédié Godot headless (ou hôte LAN). Phases : salon → préparation → journée → résultats → revanche.
1 directeur humain + 1 à 8 employés humains (+ PNJ témoins). Validation serveur des actions, cadence
limitée, données confidentielles du directeur envoyées uniquement à lui, interpolation des
déplacements, reprise de place à la reconnexion (jeton). Tests : serveur + clients bots headless.

## 7. Risques

| Risque | Mitigation |
|---|---|
| Pas de modèles 3D externes | Modélisation procédurale soignée + textures générées |
| Performances mobiles | Préréglages qualité, IA à fréquence réduite, budget physique, nombre de PNJ réglable |
| Stabilité physique | Jolt, sous-pas, masses réalistes, mise en veille |
| Pas d'appareil Android pour tester | APK signé vérifié (apksigner) ; à valider sur appareil réel |
| Multijoueur Internet | Testé en local avec plusieurs clients ; hébergement public à faire par l'utilisateur |

## 8. Stratégie de test

- `tests/run_tests.gd` (headless) : données, son, vision, soupçons, mémoire, témoignages, économie,
  sauvegarde, missions, physique (piles, chaise), simulation d'une journée complète accélérée.
- Captures d'écran automatiques (Xvfb + Vulkan logiciel) pour vérifier le rendu.
- Test multijoueur : serveur + 2–3 clients bots headless qui rejoignent, choisissent un rôle et jouent.
