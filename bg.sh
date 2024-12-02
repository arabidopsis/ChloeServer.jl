#!/bin/bash
# run `python -m chloe.background chloe-app` to create
# the "frontend" to this "backend"
if [[ $1 == "-d" ]]; then
    shift
    # logging output will be seen in terminal and not passed to backend logger...
    echo "logging to terminal"
    exec julia -t8 --project=. -e 'using ChloeServer; main()' -- --level=info --workers=2 --terminate=9799
else
    echo "logging to backend"
    exec julia -t8 --project=. -e 'using ChloeServer; main()' -- --level=info --workers=2 --backend=default --terminate=9799
fi
