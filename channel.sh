#!/usr/bin/env bash
# runs cohorts by channel

cohort=(F_VINT=2014 F_TERM=360 F_ELIG)
../00util/run_sql_v24.sh fn_cohort_v01.sql "${cohort[@]}"

for CHAN in R B C
do
    parms=("${cohort[@]}")
    parms+=(F_CHAN=${CHAN})
    parms+=(BY_AGE)
    ../00util/run_sql_v24.sh fn_cohort_v01.sql "${parms[@]}"
done

greppattern="$(for i in "${cohort[@]}";do printf "%s%s" "$i" '.*';done )"
files=($(ls _output/*.tsv  | grep "${greppattern}"))
for file in "${files[@]}"
do
    head -2 ${file} | cut -f1-3 | sed "s^$^\t${file}^"
done

