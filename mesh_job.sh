#!/bin/bash
#SBATCH --job-name=mesh_splatting_array
#SBATCH --time=2-00:00:00
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --gres=gpu:1
#SBATCH --array=0-18%5 # Launches 19 jobs (from 0 to 18), with a maximum of 5 concurrently
#SBATCH --output=resultats/resultats_%A_%a.txt # %A = Global job ID, %a = Task ID
#SBATCH --error=resultats/logs_%A_%a.txt
#SBATCH --nodelist=compute-07

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
DOSSIERS=("$DATA_DIR"/project-*)

# Select the folder corresponding to this clone's number
PROJET_PATH="${DOSSIERS[$SLURM_ARRAY_TASK_ID]}"

# Safety check in case the ID exceeds the number of folders
if [ -z "$PROJET_PATH" ] || [ ! -d "$PROJET_PATH" ]; then
    echo "End: No folder found for task n°$SLURM_ARRAY_TASK_ID"
    exit 0
fi

NOM_SCENE=$(basename "$PROJET_PATH")

echo "-------------------------------------------------------"
echo "CLONE $SLURM_ARRAY_TASK_ID : START OF PROCESSING FOR $NOM_SCENE"
echo "-------------------------------------------------------"

export PYTHONUNBUFFERED=1

# Auto-reorganization
if [ -d "$PROJET_PATH/colmap/sparse" ]; then
    mv -n "$PROJET_PATH/colmap/sparse" "$PROJET_PATH/" 2>/dev/null
    [ -f "$PROJET_PATH/colmap/database.db" ] && mv -n "$PROJET_PATH/colmap/database.db" "$PROJET_PATH/" 2>/dev/null
fi

if [ -f "$PROJET_PATH/sparse/cameras.bin" ] || [ -f "$PROJET_PATH/sparse/cameras.txt" ]; then
    mkdir -p "$PROJET_PATH/sparse/0"
    mv "$PROJET_PATH/sparse/"*.bin "$PROJET_PATH/sparse/0/" 2>/dev/null
    mv "$PROJET_PATH/sparse/"*.txt "$PROJET_PATH/sparse/0/" 2>/dev/null
fi

# Undistord
if [ ! -d "$PROJET_PATH/distorted" ]; then
    echo "Non-compliant cameras: Launching undistort process with Colmap"
    mkdir -p "$PROJET_PATH/distorted"
    
    mv "$PROJET_PATH/images" "$PROJET_PATH/distorted/"
    mv "$PROJET_PATH/sparse" "$PROJET_PATH/distorted/"

    colmap image_undistorter \
        --image_path "$PROJET_PATH/distorted/images" \
        --input_path "$PROJET_PATH/distorted/sparse/0" \
        --output_path "$PROJET_PATH" \
        --output_type COLMAP
else
    echo "Undistorting already performed."
fi

# Post-Colmap cleanup
if [ -f "$PROJET_PATH/sparse/cameras.bin" ] || [ -f "$PROJET_PATH/sparse/cameras.txt" ]; then
    mkdir -p "$PROJET_PATH/sparse/0"
    mv "$PROJET_PATH/sparse/"*.bin "$PROJET_PATH/sparse/0/" 2>/dev/null
    mv "$PROJET_PATH/sparse/"*.txt "$PROJET_PATH/sparse/0/" 2>/dev/null
fi

for IMG_DIR in "$PROJET_PATH"/images*; do
    if [ -d "$IMG_DIR" ]; then
        echo "Creating symbolic links for PNG files in $(basename "$IMG_DIR") to bypass JPG requirement..."
        cd "$IMG_DIR"
        for img in *.png; do
            [ -e "$img" ] || continue
            ln -sf "$img" "${img%.png}.jpg"
        done
        cd "$SLURM_SUBMIT_DIR" 
    fi
done

rm -rf "$OUTPUT_DIR/$NOM_SCENE"

rm -rf "$PROJET_PATH/normals"*

# Training
echo "Start of extract normals"
python mesh-splatting/extract_normals.py -s "$PROJET_PATH"

echo "Start of training"
mkdir -p "$OUTPUT_DIR/$NOM_SCENE"
python mesh-splatting/train.py -s "$PROJET_PATH" -m "$OUTPUT_DIR/$NOM_SCENE" --indoor --eval -r 2

echo "CLONE $SLURM_ARRAY_TASK_ID : END OF PROCESSING"
