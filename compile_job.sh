#!/bin/bash
#SBATCH --job-name=compile_mesh
#SBATCH --time=00:30:00
#SBATCH --ntasks=1
#SBATCH --mem=32G
#SBATCH --gpus=1
#SBATCH --output=log_compilation_finale.txt

echo "=== ACTIVATION ENVIRONNEMENT ==="
source /home/mklinkenberg/anaconda3/etc/profile.d/conda.sh
conda activate cvu-mesh

echo "=== NETTOYAGE DANS LE COEUR DE CONDA (CRUCIAL) ==="
# On désinstalle les versions compilées sur le master
pip uninstall -y diff_triangle_rasterization simple-knn effrdel
pip cache purge

echo "=== PREPARATION DEPENDANCES TEMPORAIRES ==="
pip install setuptools==69.5.1 "numpy<2.0.0" "opencv-python<4.10.0"

echo "=== 1. TRIANGLE RASTERIZER (via compile.sh) ==="
cd /home/mklinkenberg/mesh-splatting
# Nettoyage des dossiers locaux
find . -name "*.so" -delete
rm -rf submodules/diff-triangle-mesh-rasterization/build/
bash compile.sh

echo "=== 2. SIMPLE-KNN ==="
cd submodules/simple-knn
rm -rf build/ dist/ *.egg-info
pip install . --no-build-isolation --no-cache-dir

echo "=== 3. EFFRDEL ==="
cd ../effrdel
rm -rf build/ dist/ *.egg-info
pip install -e . --no-cache-dir

echo "=== RESTAURATION DEPENDANCES ==="
pip install "setuptools>=77.0.0"

echo "=== COMPILATION TOTALEMENT TERMINEE ! ==="