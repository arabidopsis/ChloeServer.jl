#!/bin/bash
if [ ! -d testo ]; then
    mkdir testo
fi
PROJECT=../chloe_biojulia
rm -rf testo/*

O='\e[0m'
G='\e[1;32m'
R='\e[1;31m'

echo "start annotations..."

time -p julia --project=$PROJECT --threads=8 "$@" $PROJECT/chloe.jl -l info annotate -o testo $PROJECT/testfa/*.fa
for f in $(ls testo)
do 
    echo "diffing $f"
    diff testo/$f $PROJECT/testfa/$f
    if [ $? -eq 0 ]; then
        echo -e "$G******** test OK ***********$O"
    else
        echo -e "$R******** test FAILED *******$O"
    fi
done
# rm -rf testo
