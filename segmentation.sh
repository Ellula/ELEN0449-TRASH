#!/bin/bash
#SBATCH --job-name=mesh_segmentation_array
#SBATCH --time=0-04:00:00 # 4h est largement suffisant pour UNE scène
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --gres=gpu:1
#SBATCH --array=0-18%5 # Vos 19 dossiers, max 5 en parallèle
#SBATCH --output=resultats/resultats_seg_%A_%a.txt
#SBATCH --error=resultats/logs_seg_%A_%a.txt
#SBATCH --nodelist=compute-01
#SBATCH --mail-user=mae.klinkenberg@student.uliege.be
#SBATCH --mail-type=END,FAIL

# Script 6

set -e

echo "Start of the script - Task ID: $SLURM_ARRAY_TASK_ID"

# Environment activation
eval "$(/home/mklinkenberg/.local/bin/micromamba shell hook --shell bash)"
export MAMBA_ROOT_PREFIX=~/micromamba/
micromamba activate mesh_splatting

DATA_DIR="$(pwd)/data" 
OUTPUT_DIR="$(pwd)/output"
export PYTHONUNBUFFERED=1

export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

# TRÈS IMPORTANT : Déplacement dans le dossier du code
cd mesh-splatting
CHEMIN_DU_MODELE_PT="/home/mklinkenberg/cvu/sam2/sam2.1_hiera_large.pt"

# Crée un lien symbolique dans le dossier courant pour que Python le trouve
if [ -f "$CHEMIN_DU_MODELE_PT" ]; then
    ln -sf "$CHEMIN_DU_MODELE_PT" .
else
    echo "ERREUR CRITIQUE : Le fichier $CHEMIN_DU_MODELE_PT est introuvable."
    exit 1
fi

# Sélection du dossier via le Slurm Array
DOSSIERS=("$DATA_DIR"/project-*)
PROJET_PATH="${DOSSIERS[$SLURM_ARRAY_TASK_ID]}"

# Sécurité
if [ -z "$PROJET_PATH" ] || [ ! -d "$PROJET_PATH" ]; then
    echo "End: No folder found for task n°$SLURM_ARRAY_TASK_ID"
    exit 0
fi

NOM_SCENE=$(basename "$PROJET_PATH")
MODEL_PATH="$OUTPUT_DIR/$NOM_SCENE"

echo "-------------------------------------------------------"
echo "CLONE $SLURM_ARRAY_TASK_ID : START OF PROCESSING FOR $NOM_SCENE"
echo "-------------------------------------------------------"

# 1. Vérifier la présence du JSON
JSON_FILE=$(ls "$MODEL_PATH"/*.sam_prompts.json 2>/dev/null | head -n 1)

if [ -z "$JSON_FILE" ]; then
    echo "⏭Pas de fichier JSON trouvé pour $NOM_SCENE. Le job s'arrête ici."
    exit 0
fi

echo "======================================================="
echo "Fichier JSON détecté : $(basename "$JSON_FILE")"
echo "======================================================="

MASKS_DIR="$MODEL_PATH/masks"

echo " Nettoyage des potentiels fichiers corrompus des anciens runs..."
rm -rf "$MASKS_DIR"
rm -f "$MODEL_PATH"/*.ply
rm -f mesh.ply object.ply

mkdir -p "$MASKS_DIR"
IMAGES_DIR="$PROJET_PATH/images" 

# --- ÉTAPES GLOBALES (1 FOIS PAR SCÈNE) ---
echo " Extraction des images..."
python -m segmentation.extract_images -s "$PROJET_PATH" -m "$MODEL_PATH" --eval

echo " Génération des masques avec SAM..."
python -m segmentation.sam_mask_generator_json --data_path "$IMAGES_DIR" --save_path "$MASKS_DIR" --json_path "$JSON_FILE"

# --- EXTRACTION DES IDs DEPUIS LE JSON ---
OBJECT_IDS=$(python -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    if isinstance(data, list):
        print(' '.join(str(obj.get('object_id', i+1)).replace('object_', '') for i, obj in enumerate(data)))
    elif isinstance(data, dict):
        print(' '.join(str(k).replace('object_', '') for k in data.keys()))
except Exception:
    print('1')
" "$JSON_FILE")

echo " Objets à traiter pour cette scène : $OBJECT_IDS"

# --- SOUS-BOUCLE POUR CHAQUE OBJET ---
for OBJECT_ID in $OBJECT_IDS; do
    echo "---------------------------------------------------"
    echo "   -> Traitement de l'objet ID : $OBJECT_ID"

    echo "   3 Identification des triangles..."
    python -m segmentation.segment -s "$PROJET_PATH" -m "$MODEL_PATH" --eval --path_mask "$MASKS_DIR" --object_id "$OBJECT_ID"
    
    echo "   4 Filtrage et rendu..."
    python -m segmentation.run_single_object -s "$PROJET_PATH" -m "$MODEL_PATH" --eval --ratio_threshold 0.90
    
    echo "   5 Création du fichier PLY..."
    python -m segmentation.create_ply "$MODEL_PATH"

    # Sécurisation du fichier généré
    # On vérifie d'abord dans le dossier courant (cas le plus probable)
    if [ -f "mesh.ply" ]; then
        mv "mesh.ply" "$MODEL_PATH/${NOM_SCENE}_object_${OBJECT_ID}.ply"
        echo "     Objet sauvegardé : ${NOM_SCENE}_objet_${OBJECT_ID}.ply"
    # Au cas où le script Python l'aurait bien mis dans MODEL_PATH
    elif [ -f "$MODEL_PATH/mesh.ply" ]; then
        mv "$MODEL_PATH/mesh.ply" "$MODEL_PATH/${NOM_SCENE}_object_${OBJECT_ID}.ply"
        echo "     Objet sauvegardé : ${NOM_SCENE}_objet_${OBJECT_ID}.ply"
    else
        echo "    Attention: Le fichier PLY généré n'a pas été trouvé. Ni dans le dossier courant, ni dans $MODEL_PATH."
    fi

done

echo " TERMINÉ POUR $NOM_SCENE"
