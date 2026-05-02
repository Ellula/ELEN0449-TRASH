#!/bin/bash
#SBATCH --job-name=mesh_splatting_all
#SBATCH --time=12:00:00            
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --gres=gpu:2
#SBATCH --output=resultats/resultats_%j.txt   # Fichier pour les textes normaux
#SBATCH --error=resultats/logs_%j.txt    # NOUVEAU : Fichier réservé aux crashs/erreurs
#SBATCH --nodelist=compute-03

# --- MODE DEBUG ACTIVÉ ---
echo "DÉMARRAGE DU SCRIPT"
echo "Je m'exécute dans ce dossier : $(pwd)"
# -------------------------

# 1. Initialisation de Micromamba (On garde ta méthode qui est la bonne)
eval "$(/home/mklinkenberg/.local/bin/micromamba shell hook --shell bash)"
export MAMBA_ROOT_PREFIX=~/micromamba/
micromamba activate mesh_splatting

# Vérification : est-ce que Python est bien là ?
echo "Version de Python trouvée :"
which python

# 2. LES CHEMINS (⚠️ UTILISE DES CHEMINS ABSOLUS)
# Remplace cette ligne par le VRAI chemin complet vers ton dossier de travail
# Exemple : DATA_DIR="/home/mklinkenberg/mon_projet_splatting/data"
DATA_DIR="$(pwd)/data" 
OUTPUT_DIR="$(pwd)/output"

echo "Je cherche les dossiers dans : $DATA_DIR"

# Vérification : est-ce que le dossier data existe vraiment ?
if [ ! -d "$DATA_DIR" ]; then
    echo "ERREUR CRITIQUE : Le dossier $DATA_DIR n'existe pas ! Arrêt du script."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# 3. La boucle
for PROJET_PATH in $DATA_DIR/project-*; do
    
    echo "Fichier/Dossier détecté : $PROJET_PATH"

    if [ -d "$PROJET_PATH" ]; then
        NOM_SCENE=$(basename "$PROJET_PATH")
        
        echo "-------------------------------------------------------"
        echo "DÉBUT DU TRAITEMENT : $NOM_SCENE"
        echo "-------------------------------------------------------"

        # On force Python à écrire en direct (pas de buffering)
        export PYTHONUNBUFFERED=1


        # --- RÉORGANISATION DES DOSSIERS COLMAP ---
        if [ -d "$PROJET_PATH/colmap/sparse/0" ]; then
            echo "Structure détectée : colmap/sparse/0. Extraction directe..."
            # On sort le contenu de '0' pour le mettre dans un dossier 'sparse' à la racine
            mkdir -p "$PROJET_PATH/sparse"
            mv "$PROJET_PATH/colmap/sparse/0/"* "$PROJET_PATH/sparse/"
            [ -f "$PROJET_PATH/colmap/database.db" ] && mv "$PROJET_PATH/colmap/database.db" "$PROJET_PATH/"
        elif [ -d "$PROJET_PATH/colmap/sparse" ]; then
            echo "Structure détectée : colmap/sparse. Remontée à la racine..."
            mv "$PROJET_PATH/colmap/sparse" "$PROJET_PATH/"
            [ -f "$PROJET_PATH/colmap/database.db" ] && mv "$PROJET_PATH/colmap/database.db" "$PROJET_PATH/"
        fi

        # ÉTAPE A : Extraire les normales
        python mesh-splatting/extract_normals.py -s "$PROJET_PATH"

        # ÉTAPE B : Lancer l'entraînement
        python mesh-splatting/train.py -s "$PROJET_PATH" -m "$OUTPUT_DIR/$NOM_SCENE" --indoor --eval

        echo "FIN DU TRAITEMENT : $NOM_SCENE"
    else
        echo "Ceci n'est pas un dossier, je l'ignore : $PROJET_PATH"
    fi
done

echo "FIN DU SCRIPT BASH"
