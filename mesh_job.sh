#!/bin/bash
#SBATCH --job-name=mesh_splatting
#SBATCH --time=24:00:00            
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --gres=gpu:2
#SBATCH --output=resultats/resultats_%j.txt
#SBATCH --error=resultats/logs_%j.txt
#SBATCH --nodelist=compute-03

# --- DEBUGGING---
echo "Start of the script"
echo "We are here: $(pwd)"

# Activation of the environnement
eval "$(/home/mklinkenberg/.local/bin/micromamba shell hook --shell bash)"
export MAMBA_ROOT_PREFIX=~/micromamba/
micromamba activate mesh_splatting

echo "Python version:"
which python

# Paths
DATA_DIR="$(pwd)/data" 
OUTPUT_DIR="$(pwd)/output"

echo "Searching for the folders in : $DATA_DIR"

if [ ! -d "$DATA_DIR" ]; then
    echo "ERROR: The folder $DATA_DIR doesn't exist! Stop."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Loop
for PROJET_PATH in $DATA_DIR/project-*; do
    
    echo "Detected folder: $PROJET_PATH"

    if [ -d "$PROJET_PATH" ]; then
        NOM_SCENE=$(basename "$PROJET_PATH")
        
        echo "-------------------------------------------------------"
        echo "START OF: $NOM_SCENE"
        echo "-------------------------------------------------------"

        export PYTHONUNBUFFERED=1

        if [ -d "$PROJET_PATH/colmap/sparse" ]; then
            echo "-> Folder colmap/sparse detected. Move it to the root."
            mv -n "$PROJET_PATH/colmap/sparse" "$PROJET_PATH/" 2>/dev/null
            [ -f "$PROJET_PATH/colmap/database.db" ] && mv -n "$PROJET_PATH/colmap/database.db" "$PROJET_PATH/" 2>/dev/null
        fi

        if [ -f "$PROJET_PATH/sparse/cameras.bin" ] || [ -f "$PROJET_PATH/sparse/cameras.txt" ]; then
            mkdir -p "$PROJET_PATH/sparse/0"
            mv "$PROJET_PATH/sparse/"*.bin "$PROJET_PATH/sparse/0/" 2>/dev/null
            mv "$PROJET_PATH/sparse/"*.txt "$PROJET_PATH/sparse/0/" 2>/dev/null
        fi

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
            
            echo "-> Undistorting completed!"
        else
            echo "-> Undistorting already performed (found 'distorted' folder)."
        fi

        if [ -f "$PROJET_PATH/sparse/cameras.bin" ] || [ -f "$PROJET_PATH/sparse/cameras.txt" ]; then
            echo "-> Moving COLMAP output files into the /0 directory..."
            mkdir -p "$PROJET_PATH/sparse/0"
            mv "$PROJET_PATH/sparse/"*.bin "$PROJET_PATH/sparse/0/" 2>/dev/null
            mv "$PROJET_PATH/sparse/"*.txt "$PROJET_PATH/sparse/0/" 2>/dev/null
        fi

        # Start of extract normals
        echo "Start of extract normals"
        python mesh-splatting/extract_normals.py -s "$PROJET_PATH"

        # Start of training
        echo "Start of training"
        python mesh-splatting/train.py -s "$PROJET_PATH" -m "$OUTPUT_DIR/$NOM_SCENE" --indoor --eval

        echo "END OF: $NOM_SCENE"
    else
        echo "This is not a folder, ignore it: $PROJET_PATH"
    fi
done

echo "END OF THE BASH SCRIPT"
