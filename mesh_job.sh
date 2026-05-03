#!/bin/bash
#SBATCH --job-name=mesh_splatting_array
#SBATCH --time=10:00:00            # 3h suffisent car chaque job ne gère qu'UNE SEULE vidéo
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --gres=gpu:2
#SBATCH --array=0-18%5             # Lance 20 jobs (de 0 à 19), avec un maximum de 5 en même temps
#SBATCH --output=resultats/resultats_%A_%a.txt  # %A = ID global du job, %a = ID de la tâche
#SBATCH --error=resultats/logs_%A_%a.txt
#SBATCH --nodelist=compute-03,compute-08

# --- DEBUGGING ---
echo "Start of the script - Task ID: $SLURM_ARRAY_TASK_ID"

# 1. Activation de l'environnement
eval "$(/home/mklinkenberg/.local/bin/micromamba shell hook --shell bash)"
export MAMBA_ROOT_PREFIX=~/micromamba/
micromamba activate mesh_splatting

# 2. Les chemins
DATA_DIR="$(pwd)/data" 
OUTPUT_DIR="$(pwd)/output"
mkdir -p "$OUTPUT_DIR"

# =========================================================
# LA MAGIE DU TABLEAU (ARRAY)
# On crée une liste de tous les dossiers "project-*"
DOSSIERS=("$DATA_DIR"/project-*)

# On sélectionne le dossier qui correspond au numéro de ce clone
PROJET_PATH="${DOSSIERS[$SLURM_ARRAY_TASK_ID]}"
# =========================================================

# Vérification de sécurité au cas où l'ID dépasse le nombre de dossiers
if [ -z "$PROJET_PATH" ] || [ ! -d "$PROJET_PATH" ]; then
    echo "Fin : Aucun dossier trouvé pour la tâche n°$SLURM_ARRAY_TASK_ID"
    exit 0
fi

NOM_SCENE=$(basename "$PROJET_PATH")
echo "-------------------------------------------------------"
echo "CLONE $SLURM_ARRAY_TASK_ID : DÉBUT DU TRAITEMENT POUR $NOM_SCENE"
echo "-------------------------------------------------------"

export PYTHONUNBUFFERED=1

# --- AUTO-RÉORGANISATION ---
if [ -d "$PROJET_PATH/colmap/sparse" ]; then
    mv -n "$PROJET_PATH/colmap/sparse" "$PROJET_PATH/" 2>/dev/null
    [ -f "$PROJET_PATH/colmap/database.db" ] && mv -n "$PROJET_PATH/colmap/database.db" "$PROJET_PATH/" 2>/dev/null
fi

if [ -f "$PROJET_PATH/sparse/cameras.bin" ] || [ -f "$PROJET_PATH/sparse/cameras.txt" ]; then
    mkdir -p "$PROJET_PATH/sparse/0"
    mv "$PROJET_PATH/sparse/"*.bin "$PROJET_PATH/sparse/0/" 2>/dev/null
    mv "$PROJET_PATH/sparse/"*.txt "$PROJET_PATH/sparse/0/" 2>/dev/null
fi

# --- UNDISTORT ---
if [ ! -d "$PROJET_PATH/distorted" ]; then
    echo "-> Non-compliant cameras: Launching undistort process with Colmap"
    mkdir -p "$PROJET_PATH/distorted"
    
    mv "$PROJET_PATH/images" "$PROJET_PATH/distorted/"
    mv "$PROJET_PATH/sparse" "$PROJET_PATH/distorted/"

    colmap image_undistorter \
        --image_path "$PROJET_PATH/distorted/images" \
        --input_path "$PROJET_PATH/distorted/sparse/0" \
        --output_path "$PROJET_PATH" \
        --output_type COLMAP
else
    echo "-> Undistorting already performed."
fi

# --- RANGEMENT POST-COLMAP ---
if [ -f "$PROJET_PATH/sparse/cameras.bin" ] || [ -f "$PROJET_PATH/sparse/cameras.txt" ]; then
    mkdir -p "$PROJET_PATH/sparse/0"
    mv "$PROJET_PATH/sparse/"*.bin "$PROJET_PATH/sparse/0/" 2>/dev/null
    mv "$PROJET_PATH/sparse/"*.txt "$PROJET_PATH/sparse/0/" 2>/dev/null
fi

# --- ENTRAÎNEMENT ---
echo "Start of extract normals"
python mesh-splatting/extract_normals.py -s "$PROJET_PATH"

echo "Start of training"
python mesh-splatting/train.py -s "$PROJET_PATH" -m "$OUTPUT_DIR/$NOM_SCENE" --indoor --eval

echo "CLONE $SLURM_ARRAY_TASK_ID : FIN DU TRAITEMENT"
