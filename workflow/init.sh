#!/bin/bash

# NOTE: raw data locations:
# FTP: /nfs/ftp/private/indigene_ftp/upload/behaviour/transfer/F2
# To copy all movies in sub-folders to a single directory:
mkdir -p /nfs/ftp/private/indigene_ftp/upload/behaviour/transfer/F2/Kiyosu_all
cp /nfs/ftp/private/indigene_ftp/upload/behaviour/transfer/F2/Kiyosu\ Movies/2022*/* /nfs/ftp/private/indigene_ftp/upload/behaviour/transfer/F2/Kiyosu_all

####################
# Codon cluster
####################

ssh codon
module load singularity-3.7.0-gcc-9.3.0-dp5ffrp
bsub -Is bash
# If needing to copy videos from FTP (rule copy_videos),
# Need to use the datamover queue so that it can see the FTP drive:
# bsub -M 20000 -q datamover -Is bash
cd /hps/software/users/birney/ian/repos/Kiyosu_CC
conda activate snakemake_6.15.5
# Regular
snakemake \
  --jobs 5000 \
  --latency-wait 100 \
  --cluster-config config/cluster.yaml \
  --cluster 'bsub -g /snakemake_bgenie -J {cluster.name} -q {cluster.queue} -n {cluster.n} -M {cluster.memory} -o {cluster.outfile}' \
  --keep-going \
  --rerun-incomplete \
  --use-conda \
  --use-singularity \
  --restart-times 0 \
  -s workflow/Snakefile \
  -p

####################
# Fiji
####################

ssh codon
bsub -M 20000 -q gui -XF -Is bash
/hps/nobackup/birney/users/ian/software/Fiji.app/ImageJ-linux64 

####################
# Build custom containers
####################

# R
RCONT=/hps/nobackup/birney/users/ian/containers/MIKK_F0_tracking/R_4.1.2.sif
singularity build --remote \
    $RCONT \
    workflow/envs/R_4.1.2.def

# Open CV (python)
OPENCVCONT=/hps/nobackup/birney/users/ian/containers/MIKK_F2_tracking/opencv_4.5.1.sif
module load singularity-3.7.0-gcc-9.3.0-dp5ffrp
singularity build --remote \
    $OPENCVCONT \
    workflow/envs/opencv_4.5.1.def

# idtrackerai
IDCONT=/hps/nobackup/birney/users/ian/containers/MIKK_F2_tracking/idtrackerai.sif
module load singularity-3.7.0-gcc-9.3.0-dp5ffrp
singularity build --remote \
    $IDCONT \
    workflow/envs/idtrackerai.def

####################
# Run RStudio Server
####################

ssh proxy-codon
bsub -q datamover -M 50000 -Is bash
module load singularity-3.7.0-gcc-9.3.0-dp5ffrp
RCONT=/hps/nobackup/birney/users/ian/containers/MIKK_F0_tracking/R_4.1.2.sif
singularity shell --bind /hps/nobackup/birney/users/ian/rstudio_db:/var/lib/rstudio-server \
                  --bind /hps/nobackup/birney/users/ian/tmp:/tmp \
                  --bind /hps/nobackup/birney/users/ian/run:/run \
                  $CONT

rserver \
    --rsession-config-file /hps/software/users/birney/ian/repos/MIKK_F0_tracking/workflow/envs/rsession.conf \
    --server-user brettell

ssh -L 8787:hl-codon-37-04:8787 proxy-codon

####################
# Run idtrackerai
####################

## GUI
ssh codon
bsub -M 10000 -q gui -XF -Is bash
module load singularity-3.7.0-gcc-9.3.0-dp5ffrp
singularity shell docker://saulpierottiebi/idtrackerai_cpu_gui:latest
idtrackerai

## Terminal mode
singularity shell docker://saulpierottiebi/idtrackerai_cpu_gui:latest
INPUT_VIDEO=/nfs/research/birney/users/ian/MIKK_F0_tracking/split/open_field/20191121_1454_iCab_L_C_q4.mp4
VID_LENGTH=18178
idtrackerai terminal_mode \
            --_video $INPUT_VIDEO \
            --_bgsub 'True' \
            --_range [0,$VID_LENGTH] \
            --_session 20191121_1454_iCab_L_C_q4 \
            --exec track_video

# convert to .csv
python /hps/software/users/birney/ian/repos/MIKK_F0_tracking/workflow/scripts/trajectories_to_csv.py /nfs/research/birney/users/ian/MIKK_F0_tracking/split/open_field/session_20191121_1454_iCab_L_C_q4

idtrackerai terminal_mode \
            --_video $INPUT_VIDEO \
            --_bgsub 'True' \
            --_intensity [$int_floor,$int_ceiling] \
            --_area [$area_floor,$area_ceiling] \
            --_range [0,$vid_length] \
            --_nblobs 2 \
            --_session $in_sample \
            --exec track_video 

####################
# Copy videos from cluster to local
####################

# To set OF and NO start/end times
rsync -aP brettell@codon:/hps/nobackup/birney/users/ian/Kiyosu_CC/recoded ~/Desktop/Kiyosu_videos

# To set tracking parameters
rsync -aP brettell@codon:/hps/nobackup/birney/users/ian/Kiyosu_CC/split ~/Desktop/Kiyosu_videos

## After tracking, to exclude copying idtrackerai files
rsync -aP -m --exclude "*/session*" --include "*/*.avi" brettell@codon:/hps/nobackup/birney/users/ian/Kiyosu_CC/split ~/Downloads/PhD_videos/Kiyosu_CC