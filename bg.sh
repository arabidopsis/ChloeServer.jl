#!/bin/bash
# run `python -m chloe.background chloe-app` to create
# the "frontend" to this "backend"
# exec julia -t8 --project=. -e 'using ChloeServer; main()' -- --level=info --workers=2 --backend=default --terminate=9999
exec julia -t8 --project=. -e 'using ChloeServer; main()' -- --level=info --workers=2 --terminate=9799
