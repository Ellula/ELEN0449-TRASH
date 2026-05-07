#!/bin/bash
#SBATCH --job-name=mesh_splatting_S8_V2
#SBATCH --time=2-00:00:00
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --gres=gpu:1
#SBATCH --output=resultats/resultats_%j.txt # %j = Job ID classique
#SBATCH --error=resultats/logs_%j.txt
#SBATCH --nodelist=compute-07

# Debugging
echo "Start of the script - Single Job"

# Environment activation
eval "$(/home/mklinkenberg/.local/bin/micromamba shell hook --shell bash)"
export MAMBA_ROOT_PREFIX=~/micromamba/
micromamba activate mesh_splatting

# Paths
DATA_DIR="$(pwd)/data" 
OUTPUT_DIR="$(pwd)/output"
mkdir -p "$OUTPUT_DIR"

PROJET_PATH="$DATA_DIR/project-S8_V2"

# Safety check
if [ ! -d "$PROJET_PATH" ]; then
    echo "Erreur : Le dossier $PROJET_PATH n'existe pas."
    exit 1
fi

NOM_SCENE=$(basename "$PROJET_PATH")

echo "START OF PROCESSING FOR $NOM_SCENE"

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

echo "END OF PROCESSING FOR $NOM_SCENE"
