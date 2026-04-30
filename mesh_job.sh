#!/bin/bash
#SBATCH --job-name=mesh_batch
#SBATCH --time=12:00:00
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --output=resultats/resultats_%j.txt
#SBATCH --gpus=1

# 1. Environnement
CONDA_PATH=$(which conda)
source $(dirname $CONDA_PATH)/../etc/profile.d/conda.sh
conda activate cvu-mesh

# Sécurité pour les vieux CPU
export ATEN_CPU_CAPABILITY=default
export MKL_DEBUG_CPU_TYPE=5

# 2. Chemins
ROOT_DIR=$(pwd)
SCRIPT_DIR="$ROOT_DIR/../mesh-splatting"
DATA_DIR="$ROOT_DIR/data"
OUTPUT_DIR="$ROOT_DIR/output"

# AJOUT CRUCIAL : On déclare les sous-modules pour Python
export PYTHONPATH="$SCRIPT_DIR:$SCRIPT_DIR/submodules/diff-gaussian-rasterization:$SCRIPT_DIR/submodules/simple-knn:$PYTHONPATH"

mkdir -p "$OUTPUT_DIR"

# 3. Réinstallation de secours (à ne faire qu'une fois si ça crash encore)
# Si tu veux tenter une recompilation propre sur le nœud :
# cd "$SCRIPT_DIR/submodules/diff-gaussian-rasterization" && pip install -e .
# cd "$SCRIPT_DIR/submodules/simple-knn" && pip install -e .
# cd "$SCRIPT_DIR"

# echo ">>> Réinstallation des modules sur le nœud de calcul..."
# cd "$SCRIPT_DIR/submodules/diff-gaussian-rasterization" && pip install -q -e .
# cd "$SCRIPT_DIR/submodules/simple-knn" && pip install -q -e .
# cd "$SCRIPT_DIR"

# 4. Boucle de traitement
for PROJET_PATH in "$DATA_DIR"/project-*; do
    if [ -d "$PROJET_PATH" ]; then
        NOM_PROJET=$(basename "$PROJET_PATH")
        SCENE_OUTPUT="$OUTPUT_DIR/$NOM_PROJET"
        mkdir -p "$SCENE_OUTPUT"

        echo "-------------------------------------------------------"
        echo "TRAITEMENT RÉEL : $NOM_PROJET"
        echo "-------------------------------------------------------"

        cd "$SCRIPT_DIR"

        # ÉTAPE A : Normales
        python extract_normals.py -s "$PROJET_PATH"

        # ÉTAPE B : Entraînement
        # On enlève --quiet pour voir EXACTEMENT où ça crash si ça recommence
        echo ">>> Lancement de l'entraînement..."
        python train.py -s "$PROJET_PATH" -i images_4 -m "$SCENE_OUTPUT" --eval --test_iterations -1

        # ... (le reste du script : render et metrics)
    fi
done