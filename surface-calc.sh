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
    local clc=$(echo "$1" | sed -s 's/·/*/g' | sed -e 's/[eE]+*/\*10\^/g' )
    echo 'scale=6 ;' "$clc" | bc -l
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

# Subtract original label and count discrepant voxels
vi=$( calculate-element-wise i.nii.gz -sub $label -abs -o di.nii.gz -sum | cut -d = -f 2)
vj=$( calculate-element-wise j.nii.gz -sub $label -abs -o dj.nii.gz -sum | cut -d = -f 2)
vk=$( calculate-element-wise k.nii.gz -sub $label -abs -o dk.nii.gz -sum | cut -d = -f 2)
## Three discrepancies in a single voxel: how many and where?
threes=$( calculate-element-wise di.nii.gz -add dj.nii.gz -add dk.nii.gz -label 3 -set 1 -o dijkthrees.nii.gz -sum | cut -d = -f 2 )
## Two discrepancies in a single voxel: how many?
twosij=$( calculate-element-wise di.nii.gz -add dj.nii.gz -mask dijkthrees.nii.gz 1 -pad 0 -reset-mask -map 1 0 2 1 -sum | cut -d = -f 2 )
twosik=$( calculate-element-wise di.nii.gz -add dk.nii.gz -mask dijkthrees.nii.gz 1 -pad 0 -reset-mask -map 1 0 2 1 -sum | cut -d = -f 2 )
twosjk=$( calculate-element-wise dj.nii.gz -add dk.nii.gz -mask dijkthrees.nii.gz 1 -pad 0 -reset-mask -map 1 0 2 1 -sum | cut -d = -f 2 )
## Ones are all those that have discrepancies but aren't twos or threes
onesi=$vi-$threes-$twosij-$twosik
onesj=$vj-$threes-$twosij-$twosjk
onesk=$vk-$threes-$twosik-$twosjk

# Threes' surface according to Heron's formula
sqi=$( echo '(' $dimi '^2 )' )
sqj=$( echo '(' $dimj '^2 )' )
sqk=$( echo '(' $dimk '^2 )' )
sqa=$( echo '(' $sqi + $sqj ')' )
sqb=$( echo '(' $sqi + $sqk ')' )
sqc=$( echo '(' $sqj + $sqk ')' )
single3area=$( echo '1/4 · sqrt( 4 · ((' $sqa '·' $sqb ') + (' $sqa '·' $sqc ') + (' $sqb '·' $sqc ')) - (' $sqa + $sqb + $sqc ')^2 )' ) 
threesarea=$( echo $single3area · $threes )

# Twos' surface depends on direction of translation
aij=$( echo 'sqrt(' $sqi + $sqj ') ·' $dimk '·' $twosij )
aik=$( echo 'sqrt(' $sqi + $sqk ') ·' $dimj '·' $twosik )
ajk=$( echo 'sqrt(' $sqj + $sqk ') ·' $dimi '·' $twosjk )
twosarea=$( echo $aij + $aik + $ajk )

# Ones' surface is the product of the two dimensions along which we haven't moved
onesiarea=$( echo '(' $dimj '·' $dimk '· (' $onesi '))')
onesjarea=$( echo '(' $dimi '·' $dimk '· (' $onesj '))')
oneskarea=$( echo '(' $dimi '·' $dimj '· (' $onesk '))' )

# Add it all up
#set -vx
surface=$( echo $threesarea + $twosarea + $onesiarea + $onesjarea + $oneskarea )
surface=$( mybc "$surface" )

# Old Manhattan-style surface calculation (simple, but overestimating
#surfc=$( echo '(' $dimj '·' $dimk '·' '(' $vi '))' '+ (' $dimi '·' $dimk '· (' $vj ')) + (' $dimi '·' $dimj '· (' $vk '))' )
#surf=$(mybc "$surfc")

labelvolvoxels=$( calculate-element-wise $label -sum | cut -d = -f 2 )
labelvolmm3=$( echo $labelvolvoxels '·' $dimi '·' $dimj '·' $dimk )
labelvolmm3=$(mybc "$labelvolmm3")
# oldsvr=$( echo $surf '/ (' $labelvolmm3 ')' )
# oldsvr=$(mybc "$oldsvr")

svr=$( echo $surface / $labelvolmm3 )
svr=$( mybc "$svr" )

echo Name,Volume_mm^3,Surface_mm^2,SVR
echo -n $bn,
echo -n $labelvolmm3,
echo -n $surface,
echo $svr

exit 0

