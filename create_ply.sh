#!/bin/bash
#SBATCH --job-name=create_ply
#SBATCH --time=0-5:00:00
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --gres=gpu:1
#SBATCH --array=0-17%5
#SBATCH --output=resultats/resultats_%A_%a.txt # %A = Global job ID, %a = Task ID
#SBATCH --error=resultats/logs_%A_%a.txt

# Script 3

# Debugging
echo "Start of the script - Task ID: $SLURM_ARRAY_TASK_ID"

# Environment activation
eval "$(/home/mklinkenberg/.local/bin/micromamba shell hook --shell bash)"
export MAMBA_ROOT_PREFIX=~/micromamba/
micromamba activate mesh_splatting

# Paths
DATA_DIR="$(pwd)/data" 
OUTPUT_DIR="$(pwd)/output"
mkdir -p "$OUTPUT_DIR"

# Create a list of all "project-*" folders
FOLDERS=("$DATA_DIR"/project-*)

# Select the folder corresponding to this clone's number
PROJET_PATH="${FOLDERS[$SLURM_ARRAY_TASK_ID]}"

# Safety check in case the ID exceeds the number of folders
if [ -z "$PROJET_PATH" ] || [ ! -d "$PROJET_PATH" ]; then
    echo "End: No folder found for task n°$SLURM_ARRAY_TASK_ID"
    exit 0
fi

NOM_SCENE=$(basename "$PROJET_PATH")

echo "CLONE $SLURM_ARRAY_TASK_ID : START OF PROCESSING FOR $NOM_SCENE"

export PYTHONUNBUFFERED=1

ITERATION_DIR="$OUTPUT_DIR/$NOM_SCENE/point_cloud/iteration_30000"

if [ ! -d "$ITERATION_DIR" ]; then
    echo "Error: iteration_30000 not found for $NOM_SCENE"
    exit 1
fi

# Create ply
echo "Start of create ply"
python mesh-splatting/create_ply.py "$ITERATION_DIR" --out "$OUTPUT_DIR/$NOM_SCENE/${NOM_SCENE}_mesh.ply"

echo "CLONE $SLURM_ARRAY_TASK_ID : END OF CREATE PLY"
