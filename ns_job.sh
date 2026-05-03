#!/bin/bash
#SBATCH --job-name=colmap_hloc
#SBATCH --time=24:00:00            
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --gres=gpu:1
#SBATCH --output=resultats/resultats_%j.txt


# Environment Initialization
echo "Initializing environment..."
source ~/anaconda3/etc/profile.d/conda.sh
conda activate cvu-mesh

# Launching AI-based extraction
echo "Launching ns-process-data with hloc"
ns-process-data video --data $(pwd)/data/S1_V2.mp4 --output-dir $(pwd)/data/project-S1_V2 --sfm-tool hloc

for f in $(pwd)/data/S[2-9]*.mp4; do 
    base=$(basename "$f" .mp4)
    echo "Launching ns-process-data with hloc for $base"
    ns-process-data video --data "$f" --output-dir "$(pwd)/data/project-$base" --sfm-tool hloc
done

echo "Processing finished"
