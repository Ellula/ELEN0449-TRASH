#!/bin/bash
#SBATCH --job-name=colmap_hloc
#SBATCH --time=30:00:00            
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --gres=gpu:1
#SBATCH --output=resultats/resultats_%j.txt

# Script 1

# Environment Initialization
echo "Initializing environment..."
source ~/anaconda3/etc/profile.d/conda.sh
conda activate cvu-mesh

# Launching AI-based extraction
for f in $(pwd)/data/S[1-9]*.mp4; do 
    base=$(basename "$f" .mp4)
    echo "Launching ns-process-data with hloc for $base"
    ns-process-data video --data "$f" --output-dir "$(pwd)/data/project-$base" --sfm-tool hloc
done

echo "Processing finished"
