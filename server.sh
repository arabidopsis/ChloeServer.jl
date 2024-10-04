#!/bin/bash
exec julia -t8 --project=. -e 'using Chloe; distributed_main()' -- --level=info --workers=4 --broker=default --reference=~/github/chloe_references
