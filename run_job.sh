#!/bin/bash
# Lignes d'instructions pour Slurm (elles commencent par #SBATCH)
#SBATCH --job-name=job_sam3  # Le nom de votre tâche
#SBATCH --time=01:00:00            # Temps maximum alloué (ici 1 heure)
#SBATCH --ntasks=1                 # Nombre de processeurs/tâches
#SBATCH --mem=64G                  # Mémoire RAM requise (ici 64 Go)
#SBATCH --output=resultats.txt     # Le fichier où atterriront vos "print()"
#SBATCH --gpus=1

# Charger Python sur le cluster (la commande exacte peut varier sur Alan)
module load python 

# Enfin, la commande qui lance votre vrai script !
python sam3_video_predictor.py
