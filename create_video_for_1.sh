#!/bin/bash
#SBATCH --job-name=create_video_S1_V1
#SBATCH --time=0-05:00:00
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --gres=gpu:1
#SBATCH --output=resultats/resultats_%j.txt
#SBATCH --error=resultats/logs_%j.txt

# Script 3.5

# Debugging
echo "Start of the script - Single Job"

# Environment activation
eval "$(/home/mklinkenberg/.local/bin/micromamba shell hook --shell bash)"
export MAMBA_ROOT_PREFIX=~/micromamba/
micromamba activate mesh_splatting

export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

# Paths
DATA_DIR="$(pwd)/data" 
OUTPUT_DIR="$(pwd)/output"
mkdir -p "$OUTPUT_DIR"

# Project path
PROJET_PATH="$DATA_DIR/project-S1_V1"

# Safety check
if [ ! -d "$PROJET_PATH" ]; then
    echo "Erreur : The folder $PROJET_PATH doesn't exist."
    exit 1
fi

NOM_SCENE=$(basename "$PROJET_PATH")

echo "START OF PROCESSING FOR $NOM_SCENE"

python mesh-splatting/create_video.py -m "$OUTPUT_DIR/$NOM_SCENE" -s "$PROJET_PATH" -r 2

echo "END OF PROCESSING FOR $NOM_SCENE"