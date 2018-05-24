#!/bin/bash

usage () {
    msg "

    Usage: $pn 3d-label.nii.gz

    Takes a binary label image.  Calculates the surface-to-volume ratio.

    "
}

set -e
#set -vx
dn=$(dirname $0)
pn=$(basename $0)
. $dn/common

label=$(normalpath $1) ; shift
bn=$(basename $label .nii.gz)

td=$(tempdir)
cd $td

mybc () {
    local clc=$(echo "$1" | sed -e 's/[eE]+*/\*10\^/g' )
    echo 'scale=6 ;' "$clc" | bc
}

# Check for MIRTK
mirtkhelp="$(which help-rst)"
if [[ -n $mirtkhelp ]]
then
    info="$(dirname $mirtkhelp)"/info
else
    fatal "MIRTK not on path"
fi

$info $label >info.txt || fatal "Could not read input file $label"

maxintens=$(grep "Maximum.intensity" info.txt | cut -d ' ' -f 3 )
[[ $maxintens -eq 1 ]] || fatal "Need binary label file as input -- no binary label in $label"
# Read voxel size
read dimi dimk dimj < <( grep "Voxel.dimensions" info.txt | tr -s ' ' | cut -d ' ' -f 4-6 )

# Generate three dofs for translating in each direction
init-dof i.dof.gz -tx $dimi
init-dof j.dof.gz -ty $dimj
init-dof k.dof.gz -tz $dimk

# Translate
transform-image $label i.nii.gz -dofin i.dof.gz
transform-image $label j.nii.gz -dofin j.dof.gz
transform-image $label k.nii.gz -dofin k.dof.gz

# Subtract old label and count discrepant voxels
vi=$( calculate-element-wise i.nii.gz -sub $label -abs -sum | cut -d = -f 2 )
vj=$( calculate-element-wise j.nii.gz -sub $label -abs -sum | cut -d = -f 2 )
vk=$( calculate-element-wise k.nii.gz -sub $label -abs -sum | cut -d = -f 2 )

surfc=$( echo '(' $dimj '*' $dimk '*' '(' $vi '))' '+ (' $dimi '*' $dimk '* (' $vj ')) + (' $dimi '*' $dimj '* (' $vk '))' )
surf=$(mybc "$surfc")
voxelvol=$( calculate-element-wise $label -sum | cut -d = -f 2 )
volc=$( echo $voxelvol '*' $dimi '*' $dimj '*' $dimk )
vol=$(mybc "$volc")
svrc=$( echo $surf '/ (' $vol ')' )
svr=$(mybc "$svrc")

echo Name,Volume_mm^3,Surface_mm^2,SVR
echo -n $bn,
echo -n $vol,
echo -n $surf,
echo $svr

exit 0

