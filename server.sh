#!/bin/bash
exec julia -t8 --project=. -e 'using ChloeServer; main()' -- --level=info --workers=4 --broker=default
