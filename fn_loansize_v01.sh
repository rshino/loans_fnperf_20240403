#!/usr/bin/env bash
#
export cohort=(F_VINT=2014 F_ELIG UNIT=1)
export loan_sizes=(150 200 250 500 9999)
export oterms=(360)
export QSCRIPT=fn_cohort_v02.sql
#
for oterm in "${oterms[@]}" ;
do
    export loan_min=0 # make sure loan size is innermost loop!
    for loan_max in "${loan_sizes[@]}" ;
    do
	parms=("${cohort[@]}")
	parms+=(F_TERM=${oterm})
	parms+=(BALN=${loan_max})
	parms+=(BAL0=${loan_min})
	parms+=(BY_AGE)
	../00util/run_sql_v24.sh "${QSCRIPT}"  "${parms[@]}"
	loan_min=${loan_max} # make sure loan size in innermost loop!!
    done # loan_max
done # oterm

##
##
