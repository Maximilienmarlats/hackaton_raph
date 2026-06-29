# Clicker Essence — Godot 4.x

Clique pour gagner de l'essence, automatise avec des drones, et remplis le réservoir jusqu'à le faire déborder !

## Nouveautés

- **Menu compétences** : bouton 🌳 ouvre un overlay avec l'arbre de compétences (+ fermer avec ✕ ou Échap)
- **Réservoir d'essence** : se remplit visuellement au fur et à mesure — couleur bleue → orange quand il approche du max
- **Drones et icônes** : chaque automatisation achetée affiche une icône animée (🚁 mini drone, 🏭 ferme auto, ⚡ critiques, ✨ ascension)
- **Condition de victoire** : quand tous les skills sont maxés ET que tu atteins 5000 essence, le réservoir déborde avec des animations, puis l'écran de victoire affiche ton temps et ton total d'essence

## Gameplay

- Bouton central de clic
- Combo si tu cliques vite
- Critiques
- Revenus passifs (drones, ferme)
- Arbre de compétences avec prérequis (dans un menu overlay)
- Sauvegarde/chargement automatique dans `/home/[USER]/.local/share/godot/app_userdata/Clicker Skill Tree/clicker_skill_tree_save.json`

## Raccourcis clavier

| Touche | Action |
|--------|--------|
| Espace | Clic |
| S | Sauvegarder |
| R | Reset |
| Échap | Fermer le menu compétences |

## Lancer le jeu

1. Ouvre Godot 4.x
2. **Import** → sélectionne `project.godot`
3. Lance la scène principale

## Modifier les compétences

Tout est dans `scripts/Main.gd`, dictionnaire `skills`. La constante `VICTORY_ESSENCE_THRESHOLD` (défaut : 5000) contrôle le seuil de victoire.
