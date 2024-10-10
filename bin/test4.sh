#!/bin/bash
if [ ! -d testo ]; then
    mkdir testo
else
    rm -rf testo/*
fi
PROJECT=../chloe_biojulia
tfiles="$PROJECT/testfa/NC_020019.1.fa $PROJECT/testfa/NC_020318.1.fa $PROJECT/testfa/NC_020152.1.fa $PROJECT/testfa/NC_020320.1.fa"
# exec python bin/chloe.py annotate -o testo --workers=4  $tfiles
time -p julia -t8 --project=$PROJECT $PROJECT/chloe.jl -l info annotate -o testo $tfiles
for f in $(ls testo)
do 
    echo "diffing $f"
    diff testo/$f testfa/$f
    if [ $? -eq 0 ]; then
        echo -e "\e[32m******** test OK ***********\e[0m"
    else
        echo -e "\e[31m******** test FAILED *******\e[0m"
    fi
done
