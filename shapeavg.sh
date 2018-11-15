#!/bin/bash

# Shape-based averaging

nlabels=3 # Number of distinct non-background labels (todo: get from input files)

# Todo: read input files from command line
# Todo: ensure input files' geometry is identical

brake() { while true ; do j=$(jobs -r | wc -l) ; test $j -lt $1 && break ; done ; }

delimiter='     '
showthis() { 
    [[ $quiet ]] && return
    echo $1 
    calculate-element-wise $1 -delimiter "$delimiter"
    echo
}

rejectv=$(( nlabels + 1 ))
calculate-element-wise s1.nii.gz -set $rejectv -o labelmap.nii.gz
calculate-element-wise s1.nii.gz -set 500 -o totaldm.nii.gz # Default distance value should be larger than diagonal through input image

for l in $(seq 0 $nlabels) ; do

    ## Isolate label $l from label map. Add 1 to ensure that this works for background (l=0)
    avgparam=""
    ll=$(( $l+1 ))
    for s in {1..8} ; do
	echo -n $l $s.\ 
    	(
	    test -e bin-l$l-s$s.nii.gz || calculate-element-wise s$s.nii.gz -add 1 -label $ll -map $ll 1 -pad 0 -o bin-l$l-s$s.nii.gz
    	    test -e dm-l$l-s$s.nii.gz || calculate-distance-map bin-l$l-s$s.nii.gz dm-l$l-s$s.nii.gz
	) & brake 8
    done
    echo
    wait

    ## Calculate label $l's average distance map across classifiers
    set -- dm-l$l-s{1..8}.nii.gz
    ndm=$#
    set -- $(echo $*|sed 's/ / -add /g')
    thisout=meandm-l$l.nii.gz
    seg_maths $* -div $ndm $thisout
    showthis $thisout

    ## Calculate new total distance map
    thisout=newtotaldm.nii.gz
#    calculate-element-wise totaldm.nii.gz -sub meandm-l$l.nii.gz -threshold 0 -set 1 -mul meandm-l$l.nii.gz -invert-mask -set 1 -mul totaldm.nii.gz -o $thisout
    seg_maths totaldm.nii.gz -min meandm-l$l.nii.gz $thisout
    showthis $thisout

    ## Calculate difference between the new and old total distance map
    thisout=diffdm.nii.gz
    seg_maths newtotaldm.nii.gz -sub totaldm.nii.gz $thisout
    showthis $thisout

    ## Create a mask that includes all locations where the mask was updated
    thisout=update-mask.nii.gz
    seg_maths diffdm.nii.gz -uthr 0 -abs -bin $thisout
    showthis $thisout

    ## Update label map within the update mask
    thisout=newlabelmap.nii.gz
    calculate-element-wise labelmap.nii.gz -mask update-mask.nii.gz -set $l -o $thisout
    showthis $thisout

    ## Create a mask that includes all locations where the new and old total distance maps are equal
    thisout=reject-mask.nii.gz
    seg_maths diffdm.nii.gz -abs -bin -sub 1 -abs -mul update-mask.nii.gz $thisout
    showthis $thisout

    ## Update label map within the reject mask to set ambiguous locations to reject value
    thisout=newlabelmap.nii.gz
    calculate-element-wise newlabelmap.nii.gz -mask reject-mask.nii.gz -set $rejectv -o $thisout
    showthis $thisout

    cp newtotaldm.nii.gz totaldm.nii.gz
    cp newlabelmap.nii.gz labelmap.nii.gz
    cp totaldm.nii.gz totaldm-l$l.nii.gz
    cp labelmap.nii.gz labelmap-l$l.nii.gz
done

exit 0
