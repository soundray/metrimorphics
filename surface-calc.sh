#!/bin/bash

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
    echo 'scale=6 ;' "$1" | bc
}

# Read voxel size
read dimi dimk dimj < <( info $label | grep Voxel.dimensions | tr -s ' ' | cut -d ' ' -f 4-6 )

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

surfc=$( echo '(' $dimj '*' $dimk '*' '(' $vi '))' '+ (' $dimi '*' $dimk '* (' $vj ')) + (' $dimi '*' $dimj '* (' $vk '))' | sed -e 's/[eE]+*/\*10\^/g' )
surf=$(mybc "$surfc")
voxelvol=$( calculate-element-wise $label -sum | cut -d = -f 2 )
volc=$( echo $voxelvol '*' $dimi '*' $dimj '*' $dimk )
vol=$(mybc "$volc")
svrc=$( echo $surf '/ (' $vol ')' | sed -e 's/[eE]+*/\*10\^/g' )
svr=$(mybc "$svrc")

echo Name,Volume_mm^3,Surface_mm^2,SVR
echo -n $bn,
echo -n $vol,
echo -n $surf,
echo $svr

exit 0

