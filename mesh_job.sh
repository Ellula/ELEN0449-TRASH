#!/bin/bash
#SBATCH --job-name=mesh_splatting
#SBATCH --time=24:00:00            
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --gres=gpu:2
#SBATCH --output=resultats/resultats_%j.txt
#SBATCH --error=resultats/logs_%j.txt
#SBATCH --nodelist=compute-03

# --- MODE DEBUG ACTIVÉ ---
echo "DÉMARRAGE DU SCRIPT"
echo "Je m'exécute dans ce dossier : $(pwd)"
# -------------------------

# 1. Initialisation de Micromamba
eval "$(/home/mklinkenberg/.local/bin/micromamba shell hook --shell bash)"
export MAMBA_ROOT_PREFIX=~/micromamba/
micromamba activate mesh_splatting

echo "Version de Python trouvée :"
which python

# 2. LES CHEMINS
DATA_DIR="$(pwd)/data" 
OUTPUT_DIR="$(pwd)/output"

echo "Je cherche les dossiers dans : $DATA_DIR"

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

        export PYTHONUNBUFFERED=1

        # =========================================================
        # 1. AUTO-RÉORGANISATION UNIVERSELLE
        # =========================================================
        if [ -d "$PROJET_PATH/colmap/sparse" ]; then
            echo "-> Dossier colmap/sparse détecté. Déplacement à la racine..."
            mv -n "$PROJET_PATH/colmap/sparse" "$PROJET_PATH/" 2>/dev/null
            [ -f "$PROJET_PATH/colmap/database.db" ] && mv -n "$PROJET_PATH/colmap/database.db" "$PROJET_PATH/" 2>/dev/null
        fi

        if [ -f "$PROJET_PATH/sparse/cameras.bin" ] || [ -f "$PROJET_PATH/sparse/cameras.txt" ]; then
            mkdir -p "$PROJET_PATH/sparse/0"
            mv "$PROJET_PATH/sparse/"*.bin "$PROJET_PATH/sparse/0/" 2>/dev/null
            mv "$PROJET_PATH/sparse/"*.txt "$PROJET_PATH/sparse/0/" 2>/dev/null
        fi

        # =========================================================
        # 2. UNDISTORT : CONVERSION EN MODÈLE PINHOLE
        # =========================================================
        if [ ! -d "$PROJET_PATH/distorted" ]; then
            echo "-> Caméras non conformes : Lancement du redressement (Undistort) avec COLMAP..."
            mkdir -p "$PROJET_PATH/distorted"
            
            mv "$PROJET_PATH/images" "$PROJET_PATH/distorted/"
            mv "$PROJET_PATH/sparse" "$PROJET_PATH/distorted/"

            colmap image_undistorter \
                --image_path "$PROJET_PATH/distorted/images" \
                --input_path "$PROJET_PATH/distorted/sparse/0" \
                --output_path "$PROJET_PATH" \
                --output_type COLMAP
            
            echo "-> Redressement terminé !"
        else
            echo "-> Le redressement a déjà été fait précédemment (dossier 'distorted' trouvé)."
        fi

        # =========================================================
        # 3. RANGEMENT POST-COLMAP (Obligatoire pour Python)
        # =========================================================
        # L'undistorter a la fâcheuse manie de recracher les fichiers directement dans sparse/
        if [ -f "$PROJET_PATH/sparse/cameras.bin" ] || [ -f "$PROJET_PATH/sparse/cameras.txt" ]; then
            echo "-> Rangement des fichiers sortis de COLMAP dans le dossier /0..."
            mkdir -p "$PROJET_PATH/sparse/0"
            mv "$PROJET_PATH/sparse/"*.bin "$PROJET_PATH/sparse/0/" 2>/dev/null
            mv "$PROJET_PATH/sparse/"*.txt "$PROJET_PATH/sparse/0/" 2>/dev/null
        fi

        # =========================================================
        # ÉTAPE A : Extraire les normales
        echo "-> Lancement de l'extraction des normales..."
        python mesh-splatting/extract_normals.py -s "$PROJET_PATH"

        # ÉTAPE B : Lancer l'entraînement
        echo "-> Lancement de l'entraînement 3D..."
        python mesh-splatting/train.py -s "$PROJET_PATH" -m "$OUTPUT_DIR/$NOM_SCENE" --indoor --eval

        echo "FIN DU TRAITEMENT : $NOM_SCENE"
    else
        echo "Ceci n'est pas un dossier, je l'ignore : $PROJET_PATH"
    fi
done

echo "FIN DU SCRIPT BASH"
